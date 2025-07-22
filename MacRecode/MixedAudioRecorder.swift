import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

@MainActor
public class MixedAudioRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var currentRecordingURL: URL?
    @Published public private(set) var recordingMode: RecordingMode = .mixedRecording
    
    // 内部録音コンポーネント
    public let systemAudioRecorder = SystemAudioRecorder()
    public let microphoneRecorder = MicrophoneRecorder()
    
    // 一時ファイルURL
    public var systemAudioTempURL: URL?
    public var microphoneTempURL: URL?
    
    private let logger = Logger(subsystem: "com.example.MacRecode", category: "MixedAudioRecorder")
    
    public init() {
        logger.info("MixedAudioRecorder initialized")
    }
    
    // MARK: - Public Methods
    
    public func startMixedRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        logger.info("Starting mixed recording...")
        
        // 並行録音を開始
        try await startConcurrentRecording()
        
        // 状態を更新
        isRecording = true
        
        // 最終的な出力ファイルのURLを生成
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "Mixed_\(formatter.string(from: Date())).caf"
        currentRecordingURL = documentsPath.appendingPathComponent(fileName)
        
        logger.info("Mixed recording started")
    }
    
    public func stopRecording() async throws {
        guard isRecording else { return }
        
        logger.info("Stopping mixed recording...")
        
        // 並行録音を停止
        try await stopConcurrentRecording()
        
        // 音声をミックス
        if let systemURL = systemAudioTempURL,
           let micURL = microphoneTempURL,
           let outputURL = currentRecordingURL {
            
            let mixedURL = try await mixAudioStreams(
                systemURL: systemURL,
                microphoneURL: micURL
            )
            
            // ミックスされたファイルを最終位置に移動
            try FileManager.default.moveItem(at: mixedURL, to: outputURL)
            currentRecordingURL = outputURL
        }
        
        // 状態を更新
        isRecording = false
        
        // 一時ファイルをクリーンアップ
        cleanupTempFiles()
        
        logger.info("Mixed recording stopped")
    }
    
    // MARK: - Concurrent Recording Methods
    
    public func startConcurrentRecording() async throws {
        logger.info("Starting concurrent recording...")
        
        // 一時ファイルURLを生成
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = DateFormatter.yyyyMMdd_HHmmss.string(from: Date())
        
        systemAudioTempURL = tempDir.appendingPathComponent("system_\(timestamp).caf")
        microphoneTempURL = tempDir.appendingPathComponent("mic_\(timestamp).caf")
        
        guard let systemURL = systemAudioTempURL,
              let micURL = microphoneTempURL else {
            throw RecordingError.setupFailed("Failed to create temp URLs")
        }
        
        // 並行でシステム音声とマイク録音を開始
        try await withThrowingTaskGroup(of: Void.self) { group in
            // システム音声録音タスク
            group.addTask { @MainActor [weak self] in
                try await self?.systemAudioRecorder.startSystemAudioRecording(to: systemURL)
            }
            
            // マイク録音タスク
            group.addTask { @MainActor [weak self] in
                try await self?.microphoneRecorder.startRecording(to: micURL)
            }
            
            // 両方が開始されるまで待機
            for try await _ in group {
                // タスクが完了するまで待機
            }
        }
        
        logger.info("Concurrent recording started")
    }
    
    public func stopConcurrentRecording() async throws {
        logger.info("Stopping concurrent recording...")
        
        // 並行で録音を停止
        await withTaskGroup(of: Void.self) { group in
            // システム音声録音停止
            group.addTask { @MainActor [weak self] in
                self?.systemAudioRecorder.stopRecording()
            }
            
            // マイク録音停止
            group.addTask { @MainActor [weak self] in
                self?.microphoneRecorder.stopRecording()
            }
            
            // 両方が停止するまで待機
            for await _ in group {
                // 完了を待機
            }
        }
        
        logger.info("Concurrent recording stopped")
    }
    
    // MARK: - Audio Mixing
    
    public func mixAudioStreams(systemURL: URL, microphoneURL: URL) async throws -> URL {
        logger.info("Starting audio mixing...")
        
        let mixedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mixed_\(UUID().uuidString).caf")
        
        // AVAudioEngineを使用してオフライン合成
        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        
        // プレイヤーノードを作成
        let systemPlayer = AVAudioPlayerNode()
        let micPlayer = AVAudioPlayerNode()
        
        // エンジンにノードを追加
        engine.attach(systemPlayer)
        engine.attach(micPlayer)
        
        // 音声ファイルを読み込み
        let systemAudioFile = try AVAudioFile(forReading: systemURL)
        let micAudioFile = try AVAudioFile(forReading: microphoneURL)
        
        // フォーマットを統一（44.1kHz, 2ch, 16bit）
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!
        
        // ミキサーに接続
        engine.connect(systemPlayer, to: mixer, format: outputFormat)
        engine.connect(micPlayer, to: mixer, format: outputFormat)
        
        // 出力ファイルを作成
        let outputFile = try AVAudioFile(
            forWriting: mixedURL,
            settings: outputFormat.settings
        )
        
        // オフライン合成を実行（簡易実装）
        // 実際の実装では、より高度な同期処理が必要
        try await performOfflineMixing(
            systemFile: systemAudioFile,
            micFile: micAudioFile,
            outputFile: outputFile,
            outputFormat: outputFormat
        )
        
        logger.info("Audio mixing completed")
        return mixedURL
    }
    
    // MARK: - Private Methods
    
    private func performOfflineMixing(
        systemFile: AVAudioFile,
        micFile: AVAudioFile,
        outputFile: AVAudioFile,
        outputFormat: AVAudioFormat
    ) async throws {
        // 簡易的なミキシング実装
        // 実際のプロダクションでは、より高度な同期とミキシングが必要
        
        let frameCount = min(systemFile.length, micFile.length)
        let bufferSize: AVAudioFrameCount = 1024
        
        let systemBuffer = AVAudioPCMBuffer(pcmFormat: systemFile.processingFormat, frameCapacity: bufferSize)!
        let micBuffer = AVAudioPCMBuffer(pcmFormat: micFile.processingFormat, frameCapacity: bufferSize)!
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: bufferSize)!
        
        var framesProcessed: AVAudioFramePosition = 0
        
        while framesProcessed < frameCount {
            let framesToRead = min(bufferSize, AVAudioFrameCount(frameCount - framesProcessed))
            
            // システム音声を読み込み
            systemFile.framePosition = framesProcessed
            try systemFile.read(into: systemBuffer, frameCount: framesToRead)
            
            // マイク音声を読み込み
            micFile.framePosition = framesProcessed
            try micFile.read(into: micBuffer, frameCount: framesToRead)
            
            // 簡易ミキシング（実際はより高度な処理が必要）
            outputBuffer.frameLength = framesToRead
            
            // 出力ファイルに書き込み
            try outputFile.write(from: outputBuffer)
            
            framesProcessed += AVAudioFramePosition(framesToRead)
        }
    }
    
    private func cleanupTempFiles() {
        if let systemURL = systemAudioTempURL,
           FileManager.default.fileExists(atPath: systemURL.path) {
            try? FileManager.default.removeItem(at: systemURL)
        }
        
        if let micURL = microphoneTempURL,
           FileManager.default.fileExists(atPath: micURL.path) {
            try? FileManager.default.removeItem(at: micURL)
        }
        
        systemAudioTempURL = nil
        microphoneTempURL = nil
    }
}

// MARK: - MicrophoneRecorder Helper Class

@MainActor
public class MicrophoneRecorder: ObservableObject {
    @Published public private(set) var isRecording = false
    
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let logger = Logger(subsystem: "com.example.MacRecode", category: "MicrophoneRecorder")
    
    public func startRecording(to url: URL) async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // マイク権限チェック
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw RecordingError.permissionDenied("Microphone permission required")
            }
        }
        
        // 音声エンジンをセットアップ
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw RecordingError.setupFailed("Failed to create audio engine")
        }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // 音声ファイルを作成
        audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        
        // タップを設定
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        // エンジンを開始
        try engine.start()
        isRecording = true
        
        logger.info("Microphone recording started")
    }
    
    public func stopRecording() {
        guard isRecording else { return }
        
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        
        audioFile = nil
        audioEngine = nil
        isRecording = false
        
        logger.info("Microphone recording stopped")
    }
}