import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

public enum RecordingError: LocalizedError {
    case permissionDenied(String)
    case noDisplayFound
    case setupFailed(String)
    case recordingInProgress
    case screenCaptureKitError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let details):
            return "画面収録の権限が必要です。詳細: \(details)\n\nシステム環境設定 > プライバシーとセキュリティ > 画面収録 で許可してください。"
        case .noDisplayFound:
            return "録音可能なディスプレイが見つかりませんでした"
        case .setupFailed(let details):
            return "録音の設定に失敗しました: \(details)"
        case .recordingInProgress:
            return "録音が既に開始されています"
        case .screenCaptureKitError(let error):
            return "ScreenCaptureKitエラー: \(error.localizedDescription)"
        }
    }
}

@MainActor
public class SystemAudioRecorder: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?
    
    private var captureSession: SCStream?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let logger = Logger(subsystem: "com.example.MacRecode", category: "SystemAudioRecorder")
    private let recordingQueue = DispatchQueue(label: "com.example.MacRecode.recording", qos: .userInitiated)
    
    public override init() {
        super.init()
    }
    
    public func startRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // マイク権限チェック
        await requestMicrophonePermission()
        
        // 画面録画権限チェック
        let hasPermission = await checkRecordingPermission()
        guard hasPermission else {
            let preflightResult = CGPreflightScreenCaptureAccess()
            throw RecordingError.permissionDenied("Preflight: \(preflightResult)")
        }
        
        // 録音ファイルのURLを生成（Documentsフォルダに保存）
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MacRecode_\(formatter.string(from: Date())).caf"
        let recordingURL = documentsPath.appendingPathComponent(fileName)
        
        // ディレクトリが存在することを確認
        try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true, attributes: nil)
        
        do {
            // 音声エンジンのセットアップ
            try setupAudioEngine(outputURL: recordingURL)
            
            // 録音開始
            try audioEngine?.start()
            
            // 状態を更新
            currentRecordingURL = recordingURL
            isRecording = true
            
            logger.info("録音を開始しました: \(fileName)")
            logger.info("保存場所: \(recordingURL.path)")
        } catch {
            // エラー時はクリーンアップ
            stopRecording()
            if let error = error as? RecordingError {
                throw error
            } else {
                throw RecordingError.setupFailed(error.localizedDescription)
            }
        }
    }
    
    public func stopRecording() {
        guard isRecording else { return }
        
        logger.info("録音を停止中...")
        
        // 音声エンジンを停止
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)  // タップを削除
            logger.info("Audio engine stopped")
        }
        
        // 音声ファイルを閉じる
        audioFile = nil
        
        // リソースをクリーンアップ
        audioEngine = nil
        
        // 状態を更新
        isRecording = false
        
        if let url = currentRecordingURL {
            logger.info("録音を停止しました。ファイル: \(url.lastPathComponent)")
            
            // ファイルサイズを確認
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    logger.info("保存されたファイルサイズ: \(fileSize) bytes")
                }
            } catch {
                logger.error("Failed to get file size: \(error.localizedDescription)")
            }
        }
    }
    
    private func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Current microphone permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            logger.info("Microphone permission already granted")
            return
        case .notDetermined:
            logger.info("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission granted: \(granted)")
        case .denied, .restricted:
            logger.error("Microphone permission denied or restricted")
        @unknown default:
            logger.error("Unknown microphone permission status")
        }
    }
    
    public func checkRecordingPermission() async -> Bool {
        // まずプリフライトチェック
        let canRecord = CGPreflightScreenCaptureAccess()
        logger.info("Screen capture preflight check: \(canRecord)")
        
        if !canRecord {
            // 権限がない場合は要求
            logger.info("Requesting screen capture access...")
            let granted = CGRequestScreenCaptureAccess()
            logger.info("Screen capture access granted: \(granted)")
            
            // 権限要求後、少し待ってから再度確認
            if granted {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒待機
                let recheckResult = CGPreflightScreenCaptureAccess()
                logger.info("Screen capture recheck after grant: \(recheckResult)")
                return recheckResult
            }
            return granted
        }
        
        // 権限があっても、実際にScreenCaptureKitが使えるかテスト
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            logger.info("ScreenCaptureKit test successful: \(content.displays.count) displays found")
            return !content.displays.isEmpty
        } catch {
            logger.error("ScreenCaptureKit test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - System Audio Recording Methods
    
    public func checkSystemAudioPermission() async -> Bool {
        return await checkRecordingPermission()
    }
    
    public func startSystemAudioRecording() async throws {
        // デフォルトの保存先でシステム音声録音を開始
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SystemAudio_\(formatter.string(from: Date())).caf"
        let defaultURL = documentsPath.appendingPathComponent(filename)
        
        try await startSystemAudioRecording(to: defaultURL)
    }
    
    public func startSystemAudioRecording(to url: URL) async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        logger.info("Starting system audio recording to: \(url.path)")
        
        // 画面録画権限チェック  
        logger.info("Checking recording permissions...")
        let hasPermission = await checkRecordingPermission()
        logger.info("Permission check result: \(hasPermission)")
        
        guard hasPermission else {
            let preflightResult = CGPreflightScreenCaptureAccess()
            logger.error("Permission denied. Preflight result: \(preflightResult)")
            throw RecordingError.permissionDenied("Preflight: \(preflightResult)")
        }
        
        // 指定されたURLを使用
        let recordingURL = url
        
        // 保存先ディレクトリが存在することを確認
        let parentDirectory = recordingURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
        
        do {
            // ScreenCaptureKitでシステム音声キャプチャをセットアップ
            try await setupSystemAudioCapture(outputURL: recordingURL)
            
            // 状態を更新
            currentRecordingURL = recordingURL
            isRecording = true
            
            logger.info("システム音声録音を開始しました: \(recordingURL.lastPathComponent)")
            logger.info("保存場所: \(recordingURL.path)")
        } catch {
            // エラー時はクリーンアップ
            stopRecording()
            if let error = error as? RecordingError {
                throw error
            } else {
                throw RecordingError.setupFailed(error.localizedDescription)
            }
        }
    }
    
    public func supportsSystemAudioCapture() -> Bool {
        return true // ScreenCaptureKit is available on macOS 13+
    }
    
    // MARK: - Private Methods
    
    private func setupAudioEngine(outputURL: URL) throws {
        // AVAudioEngineの初期化
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw RecordingError.setupFailed("Failed to create audio engine")
        }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        logger.info("Input audio format: \(recordingFormat)")
        
        // 入力フォーマットをそのまま使用してファイル作成
        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: recordingFormat.settings)
            logger.info("Audio file created with format: \(recordingFormat)")
            logger.info("Audio file path: \(outputURL.path)")
        } catch {
            throw RecordingError.setupFailed("Failed to create audio file: \(error.localizedDescription)")
        }
        
        // 音声データをファイルに書き込むタップを設定
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            do {
                try self?.audioFile?.write(from: buffer)
            } catch {
                self?.logger.error("Failed to write audio buffer: \(error.localizedDescription)")
            }
        }
        
        logger.info("Audio engine setup completed")
    }
    
    private func setupSystemAudioCapture(outputURL: URL) async throws {
        do {
            logger.info("Getting shareable content...")
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            logger.info("Found \(content.displays.count) displays, \(content.applications.count) applications")
            
            guard let display = content.displays.first else {
                throw RecordingError.noDisplayFound
            }
            logger.info("Using display: \(display.displayID)")
            
            // 最もシンプルなフィルター設定
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            
            // オーディオのみの最小設定
            configuration.capturesAudio = true
            configuration.sampleRate = 44100
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
            
            // ビデオ設定は最小に（オーディオのみでも必要）
            configuration.width = 100
            configuration.height = 100
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            
            logger.info("Creating SCStream with audio-only config...")
            captureSession = SCStream(filter: filter, configuration: configuration, delegate: self)
            
            guard let stream = captureSession else {
                logger.error("Failed to create SCStream object")
                throw RecordingError.screenCaptureKitError(NSError(domain: "MacRecode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create SCStream"]))
            }
            logger.info("SCStream created successfully")
            
            // 音声ファイルセットアップを先に行う
            try setupSystemAudioFile(outputURL: outputURL)
            logger.info("Audio file setup completed")
            
            logger.info("Adding audio stream output...")
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: recordingQueue)
            logger.info("Audio stream output added")
            
            // キャプチャ開始前に少し待機
            logger.info("Starting ScreenCaptureKit capture...")
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms待機
            try await stream.startCapture()
            
            logger.info("ScreenCaptureKit system audio capture started successfully")
        } catch {
            logger.error("ScreenCaptureKit setup failed: \(error.localizedDescription)")
            logger.error("Error details: \(error)")
            
            // 具体的なエラー情報をログ出力
            if let nsError = error as NSError? {
                logger.error("Error domain: \(nsError.domain)")
                logger.error("Error code: \(nsError.code)")
                logger.error("Error userInfo: \(nsError.userInfo)")
            }
            
            throw RecordingError.screenCaptureKitError(error)
        }
    }
    
    private func setupSystemAudioFile(outputURL: URL) throws {
        // システム音声用の設定（PCMフォーマット）
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
            logger.info("System audio file created: \(outputURL.path)")
        } catch {
            throw RecordingError.setupFailed("Failed to create system audio file: \(error.localizedDescription)")
        }
        
        logger.info("System audio file setup completed")
    }
}

// MARK: - SCStreamOutput Protocol
extension SystemAudioRecorder {
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard self.isRecording else { return }
                
                // CMSampleBufferをAVAudioPCMBufferに変換
                guard let audioBuffer = self.createAudioBuffer(from: sampleBuffer) else {
                    self.logger.error("Failed to create audio buffer from sample buffer")
                    return
                }
                
                // ファイルに書き込み
                do {
                    try self.audioFile?.write(from: audioBuffer)
                } catch {
                    self.logger.error("Failed to write system audio buffer: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func createAudioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        
        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        guard let description = audioStreamBasicDescription else {
            return nil
        }
        
        var streamDescription = description.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        guard let audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>?
        var length: Int = 0
        
        let status = CMBlockBufferGetDataPointer(audioBlockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        
        guard status == noErr, let pointer = dataPointer else {
            return nil
        }
        
        memcpy(buffer.audioBufferList.pointee.mBuffers.mData, pointer, length)
        
        return buffer
    }
}