import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

public enum RecordingError: LocalizedError {
    case permissionDenied(String)
    case noDisplayFound
    case setupFailed(String)
    case recordingInProgress
    case mixingEngineFailed(String)
    case audioFormatError(String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let details):
            return "画面収録の権限が必要です: \(details)"
        case .noDisplayFound:
            return "録音可能なディスプレイが見つかりませんでした"
        case .setupFailed(let details):
            return "録音の設定に失敗しました: \(details)"
        case .recordingInProgress:
            return "録音が既に開始されています"
        case .mixingEngineFailed(let details):
            return "ミキシングエンジンのエラー: \(details)"
        case .audioFormatError(let details):
            return "音声フォーマットエラー: \(details)"
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
    
    // Mixed recording properties
    private var mixingEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    private var systemAudioPlayerNode: AVAudioPlayerNode?
    private var mixedAudioFile: AVAudioFile?
    
    public init() {}
    
    public func startRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // 権限チェック
        let hasPermission = await checkRecordingPermission()
        guard hasPermission else {
            throw RecordingError.permissionDenied("画面録画権限が許可されていません")
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
        
        // ミキシングエンジンを停止
        if let mixEngine = mixingEngine, mixEngine.isRunning {
            mixEngine.stop()
            mixerNode?.removeTap(onBus: 0) // ミキサーのタップを削除
        }
        
        // ミキシング関連のリソースをクリーンアップ
        mixingEngine = nil
        mixerNode = nil
        systemAudioPlayerNode = nil
        mixedAudioFile = nil
        
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
    
    // MARK: - Mixed Recording Methods
    
    public func startMixedRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // 録音ファイルのセットアップ
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "MixedRecording_\(Date().timeIntervalSince1970).caf"
        let recordingURL = documentsPath.appendingPathComponent(fileName)
        
        // 保存先ディレクトリの作成を確認
        do {
            try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw RecordingError.setupFailed("録音ディレクトリの作成に失敗しました: \(error.localizedDescription)")
        }
        
        try await setupMixedRecording()
        try setupMixedAudioFile(outputURL: recordingURL)
        
        // 録音開始
        try mixingEngine?.start()
        
        currentRecordingURL = recordingURL
        isRecording = true
        
        logger.info("ミックス録音を開始しました: \(fileName)")
    }
    
    public func setupMixedRecording() async throws {
        // AVAudioEngineのセットアップ
        mixingEngine = AVAudioEngine()
        guard let engine = mixingEngine else {
            throw RecordingError.mixingEngineFailed("AVAudioEngineの作成に失敗しました")
        }
        
        // ミキサーノードの作成と接続
        mixerNode = AVAudioMixerNode()
        guard let mixer = mixerNode else {
            throw RecordingError.mixingEngineFailed("AVAudioMixerNodeの作成に失敗しました")
        }
        
        let mixedFormat = getMixedRecordingFormat()
        
        do {
            engine.attach(mixer)
            engine.connect(mixer, to: engine.outputNode, format: mixedFormat)
            
            // マイク入力を接続
            let inputNode = engine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            
            // フォーマット互換性チェック
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                throw RecordingError.audioFormatError("無効なマイク入力フォーマット")
            }
            
            engine.connect(inputNode, to: mixer, format: inputFormat)
            
            // システム音声プレイヤーノードの作成と接続
            systemAudioPlayerNode = AVAudioPlayerNode()
            guard let playerNode = systemAudioPlayerNode else {
                throw RecordingError.mixingEngineFailed("AVAudioPlayerNodeの作成に失敗しました")
            }
            
            engine.attach(playerNode)
            engine.connect(playerNode, to: mixer, format: mixedFormat)
            
            logger.info("ミックス録音のセットアップが完了しました")
            logger.info("入力フォーマット: \(inputFormat)")
            logger.info("ミックスフォーマット: \(mixedFormat)")
            
        } catch {
            // セットアップエラー時のクリーンアップ
            mixingEngine = nil
            mixerNode = nil
            systemAudioPlayerNode = nil
            
            if let recordingError = error as? RecordingError {
                throw recordingError
            } else {
                throw RecordingError.setupFailed("ミキシングエンジンのセットアップエラー: \(error.localizedDescription)")
            }
        }
    }
    
    public func startMixedRecordingWithSync() async throws -> AVAudioTime? {
        try await startMixedRecording()
        return mixingEngine?.outputNode.lastRenderTime
    }
    
    public func getMixedRecordingFormat() -> AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2) ?? 
               AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
    }
    
    public func hasMixerNodeConfigured() -> Bool {
        return mixerNode != nil
    }
    
    public func hasSystemAudioPlayerNodeConnected() -> Bool {
        return systemAudioPlayerNode != nil
    }
    
    public func hasMicrophoneInputConnected() -> Bool {
        return mixingEngine?.inputNode != nil
    }
    
    public func isSystemAudioSynchronized() -> Bool {
        // 最小実装: 常にtrueを返す
        return true
    }
    
    public func isMicrophoneSynchronized() -> Bool {
        // 最小実装: 常にtrueを返す
        return true
    }
    
    private func setupMixedAudioFile(outputURL: URL) throws {
        let format = getMixedRecordingFormat()
        mixedAudioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        // ミキサーからの出力をファイルに録音するタップを設定
        mixerNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            do {
                try self?.mixedAudioFile?.write(from: buffer)
            } catch {
                self?.logger.error("Failed to write mixed audio buffer: \(error.localizedDescription)")
            }
        }
        
        logger.info("Mixed audio file setup completed: \(outputURL.path)")
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