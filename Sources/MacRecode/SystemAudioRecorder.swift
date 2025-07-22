import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

public enum RecordingError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case setupFailed
    case recordingInProgress
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "画面収録の権限が必要です"
        case .noDisplayFound:
            return "録音可能なディスプレイが見つかりませんでした"
        case .setupFailed:
            return "録音の設定に失敗しました"
        case .recordingInProgress:
            return "録音が既に開始されています"
        }
    }
}

@MainActor
public class SystemAudioRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?
    
    private var captureSession: SCStream?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let logger = Logger(subsystem: "com.example.MacRecode", category: "SystemAudioRecorder")
    
    public init() {}
    
    public func startRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // 権限チェック
        let hasPermission = await checkRecordingPermission()
        guard hasPermission else {
            throw RecordingError.permissionDenied
        }
        
        // 録音ファイルのURLを生成
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let recordingURL = documentsPath.appendingPathComponent(fileName)
        
        // 状態を更新
        currentRecordingURL = recordingURL
        isRecording = true
        
        logger.info("録音を開始しました: \(fileName)")
    }
    
    public func stopRecording() {
        guard isRecording else { return }
        
        // セッションをクリーンアップ
        captureSession?.stopCapture()
        captureSession = nil
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        
        // 状態を更新
        isRecording = false
        
        logger.info("録音を停止しました")
    }
    
    public func checkRecordingPermission() async -> Bool {
        // ScreenCaptureKitの権限をチェック
        let canRecord = CGPreflightScreenCaptureAccess()
        if !canRecord {
            // 権限がない場合は要求
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
    
    // MARK: - Private Methods
    
    private func setupScreenCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        
        guard let display = content.displays.first else {
            throw RecordingError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        
        // 音声のみキャプチャするように設定
        configuration.capturesAudio = true
        configuration.sampleRate = 44100
        configuration.channelCount = 2
        
        captureSession = SCStream(filter: filter, configuration: configuration, delegate: nil)
    }
}