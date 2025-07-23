import Foundation
import AVFoundation
import ScreenCaptureKit
import OSLog

public enum RecordingMode {
    case microphoneOnly
    case systemAudioOnly
    case mixedRecording
}

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
    @Published public private(set) var recordingMode: RecordingMode = .systemAudioOnly
    
    private var captureSession: SCStream?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    
    // ミックス録音用の分離された変数
    private var microphoneEngine: AVAudioEngine?
    private var microphoneFile: AVAudioFile?
    
    // ミックス録音時の一時ファイルURL
    private var systemTempURL: URL?
    private var micTempURL: URL?
    private var finalMixedURL: URL?
    private let logger = Logger(subsystem: "com.example.MacRecode", category: "SystemAudioRecorder")
    private let recordingQueue = DispatchQueue(label: "com.example.MacRecode.recording", qos: .userInitiated)
    private var lastAudioLogTime: Date?
    
    public override init() {
        super.init()
    }
    
    // MARK: - Recording Mode Management
    
    public func setRecordingMode(_ mode: RecordingMode) {
        guard !isRecording else { return }
        recordingMode = mode
    }
    
    // MARK: - Mixed Recording Integration
    
    public func startRecordingWithMode() async throws {
        switch recordingMode {
        case .systemAudioOnly:
            try await startSystemAudioRecording()
        case .microphoneOnly:
            try await startMicrophoneRecording()
        case .mixedRecording:
            // 真のミックス録音: システム音声とマイクを並行録音
            logger.info("Mixed recording selected - starting dual audio capture")
            try await startMixedRecording()
        }
    }
    
    // MARK: - Microphone Recording Methods
    
    public func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.info("Current microphone permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            logger.info("Microphone permission already granted")
            return true
        case .notDetermined:
            logger.info("Requesting microphone permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("Microphone permission granted: \(granted)")
            return granted
        case .denied, .restricted:
            logger.error("Microphone permission denied or restricted")
            return false
        @unknown default:
            logger.error("Unknown microphone permission status")
            return false
        }
    }
    
    public func startMicrophoneRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // マイク権限をチェック
        let hasPermission = await checkMicrophonePermission()
        guard hasPermission else {
            throw RecordingError.permissionDenied("Microphone permission required")
        }
        
        // 録音ファイルのURLを生成（Documentsフォルダに保存）
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "Microphone_\(formatter.string(from: Date())).caf"
        let recordingURL = documentsPath.appendingPathComponent(fileName)
        
        // ディレクトリが存在することを確認
        try FileManager.default.createDirectory(at: documentsPath, withIntermediateDirectories: true, attributes: nil)
        
        do {
            // マイク録音のセットアップ
            try setupMicrophoneAudioEngine(outputURL: recordingURL)
            
            // 録音開始
            try audioEngine?.start()
            
            // 状態を更新
            currentRecordingURL = recordingURL
            isRecording = true
            
            logger.info("マイク録音を開始しました: \(fileName)")
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
        
        // ScreenCaptureKit セッションを停止
        Task {
            do {
                try await captureSession?.stopCapture()
            } catch {
                self.logger.error("Failed to stop capture session: \(error)")
            }
        }
        captureSession = nil
        
        // 音声ファイルを閉じる
        audioFile = nil
        
        // リソースをクリーンアップ
        audioEngine = nil
        microphoneEngine = nil
        microphoneFile = nil
        systemTempURL = nil
        micTempURL = nil
        finalMixedURL = nil
        
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
        logger.info("🔐 Checking screen recording permissions...")
        let hasPermission = await checkRecordingPermission()
        logger.info("🔐 Permission check result: \(hasPermission)")
        
        if !hasPermission {
            let preflightResult = CGPreflightScreenCaptureAccess()
            logger.error("🚫 Screen recording permission denied. Preflight: \(preflightResult)")
            
            // より詳細な権限チェック
            if !preflightResult {
                logger.error("⚠️  Please grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording")
            }
            
            throw RecordingError.permissionDenied("Screen Recording permission required. Check System Settings > Privacy & Security > Screen Recording")
        }
        
        logger.info("✅ Screen recording permission confirmed")
        
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
            
            // システム音声キャプチャ用のフィルター設定
            // 全てのアプリケーションの音声を含める
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            
            // システム音声キャプチャ設定
            configuration.capturesAudio = true
            configuration.sampleRate = 44100
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true // 自分のアプリの音声は除外
            
            // ビデオ設定は最小に（オーディオのみでも必要）
            configuration.width = 100
            configuration.height = 100
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            
            logger.info("Creating SCStream with system audio config...")
            logger.info("Audio capture enabled: \(configuration.capturesAudio)")
            logger.info("Sample rate: \(configuration.sampleRate), Channels: \(configuration.channelCount)")
            logger.info("Excludes current process audio: \(configuration.excludesCurrentProcessAudio)")
            
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
        logger.info("🗂 Creating system audio file: \(outputURL.lastPathComponent)")
        
        // より互換性の高いCAFフォーマット設定
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        // ディレクトリの存在確認と作成
        let parentDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            logger.info("📁 Created directory: \(parentDir.path)")
        }
        
        // 既存ファイルがあれば削除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
            logger.info("🗑 Removed existing file: \(outputURL.lastPathComponent)")
        }
        
        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
            logger.info("✅ System audio file created successfully: \(outputURL.path)")
        } catch {
            logger.error("❌ Failed to create system audio file: \(error)")
            logger.error("   URL: \(outputURL.path)")
            logger.error("   Settings: \(settings)")
            throw RecordingError.setupFailed("Failed to create system audio file: \(error.localizedDescription)")
        }
        
        logger.info("System audio file setup completed")
    }
    
    private func setupMicrophoneAudioEngine(outputURL: URL) throws {
        logger.info("🎤 Creating microphone audio engine...")
        
        // ミックス録音用の分離されたAVAudioEngineを初期化
        microphoneEngine = AVAudioEngine()
        guard let engine = microphoneEngine else {
            throw RecordingError.setupFailed("Failed to create microphone audio engine")
        }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        logger.info("Microphone input audio format: \(recordingFormat)")
        
        // ディレクトリの存在確認
        let parentDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        // 既存ファイルがあれば削除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
            logger.info("🗑 Removed existing microphone file: \(outputURL.lastPathComponent)")
        }
        
        // マイク用音声ファイルを作成（分離された変数を使用）
        do {
            microphoneFile = try AVAudioFile(forWriting: outputURL, settings: recordingFormat.settings)
            logger.info("✅ Microphone audio file created: \(outputURL.path)")
        } catch {
            logger.error("❌ Failed to create microphone audio file: \(error)")
            throw RecordingError.setupFailed("Failed to create microphone audio file: \(error.localizedDescription)")
        }
        
        // 音声データをファイルに書き込むタップを設定（分離された変数を使用）
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            do {
                try self?.microphoneFile?.write(from: buffer)
            } catch {
                self?.logger.error("Failed to write microphone audio buffer: \(error.localizedDescription)")
            }
        }
        
        logger.info("✅ Microphone audio engine setup completed")
    }
    
    // MARK: - Mixed Recording Implementation
    
    private func startMixedRecording() async throws {
        guard !isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        logger.info("Starting mixed recording (system audio + microphone)...")
        
        // 両方の権限をチェック
        let hasSystemPermission = await checkRecordingPermission()
        guard hasSystemPermission else {
            throw RecordingError.permissionDenied("System audio permission required")
        }
        
        let hasMicPermission = await checkMicrophonePermission()
        guard hasMicPermission else {
            throw RecordingError.permissionDenied("Microphone permission required")
        }
        
        // 一時ファイルのURLを生成（デスクトップに保存して確認しやすくする）
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        
        let systemTempURL = desktopPath.appendingPathComponent("system_\(timestamp).caf")
        let micTempURL = desktopPath.appendingPathComponent("mic_\(timestamp).caf")
        let finalMixedURL = desktopPath.appendingPathComponent("Mixed_\(timestamp).caf")
        
        logger.info("🗂 Mixed recording temp files:")
        logger.info("  System: \(systemTempURL.path)")
        logger.info("  Mic: \(micTempURL.path)")
        logger.info("  Final: \(finalMixedURL.path)")
        
        // ディレクトリを確保
        try FileManager.default.createDirectory(at: desktopPath, withIntermediateDirectories: true, attributes: nil)
        
        // 並行録音を開始
        try await startDualRecording(systemURL: systemTempURL, micURL: micTempURL)
        
        // 状態を更新
        currentRecordingURL = finalMixedURL
        isRecording = true
        
        // 一時ファイルのパスを保存（停止時のミックス処理のため）
        self.systemTempURL = systemTempURL
        self.micTempURL = micTempURL
        self.finalMixedURL = finalMixedURL
        
        logger.info("Mixed recording started successfully")
    }
    
    private func startDualRecording(systemURL: URL, micURL: URL) async throws {
        logger.info("🔧 Setting up dual recording...")
        
        // 順次セットアップ（同時実行による競合を避ける）
        logger.info("📻 Setting up system audio capture...")
        try await setupSystemAudioCapture(outputURL: systemURL)
        logger.info("✅ System audio capture setup complete")
        
        // 少し待機してからマイクをセットアップ
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms待機
        
        logger.info("🎤 Setting up microphone recording...")
        try setupMicrophoneAudioEngine(outputURL: micURL)
        logger.info("✅ Microphone recording setup complete")
        
        // マイク録音エンジンを開始（分離されたエンジンを使用）
        logger.info("🚀 Starting microphone audio engine...")
        try microphoneEngine?.start()
        logger.info("✅ Dual recording setup completed successfully")
    }
    
    public func stopMixedRecording() async throws {
        guard isRecording else { return }
        
        logger.info("Stopping mixed recording...")
        
        // マイク録音エンジンを停止（分離されたエンジン）
        if let micEngine = microphoneEngine, micEngine.isRunning {
            micEngine.stop()
            micEngine.inputNode.removeTap(onBus: 0)
            logger.info("✅ Microphone engine stopped")
        }
        
        // システム音声録音を停止
        Task {
            do {
                try await captureSession?.stopCapture()
                self.logger.info("✅ System audio capture stopped")
            } catch {
                self.logger.error("Failed to stop capture session: \(error)")
            }
        }
        
        // リソースをクリーンアップ
        captureSession = nil
        audioFile = nil
        microphoneFile = nil
        microphoneEngine = nil
        
        // 音声ファイルをミックス
        guard let systemURL = systemTempURL,
              let micURL = micTempURL,
              let outputURL = finalMixedURL else {
            throw RecordingError.setupFailed("Missing temp file URLs")
        }
        
        try await mixAudioFiles(systemURL: systemURL, micURL: micURL, outputURL: outputURL)
        
        // 一時ファイルをクリーンアップ
        cleanupTempFiles(systemURL: systemURL, micURL: micURL)
        
        // 状態をリセット
        isRecording = false
        self.systemTempURL = nil
        self.micTempURL = nil
        self.finalMixedURL = nil
        
        logger.info("Mixed recording completed and mixed")
    }
    
    private func mixAudioFiles(systemURL: URL, micURL: URL, outputURL: URL) async throws {
        logger.info("Mixing audio files...")
        
        // AVAudioEngineでオフラインミキシング
        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        
        // プレイヤーノードを作成
        let systemPlayer = AVAudioPlayerNode()
        let micPlayer = AVAudioPlayerNode()
        
        engine.attach(systemPlayer)
        engine.attach(micPlayer)
        
        // 音声ファイルを読み込み
        guard FileManager.default.fileExists(atPath: systemURL.path) else {
            throw RecordingError.setupFailed("System audio file not found")
        }
        
        guard FileManager.default.fileExists(atPath: micURL.path) else {
            throw RecordingError.setupFailed("Microphone file not found")
        }
        
        let systemFile = try AVAudioFile(forReading: systemURL)
        let micFile = try AVAudioFile(forReading: micURL)
        
        // 出力フォーマット（統一）
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        ) else {
            throw RecordingError.setupFailed("Failed to create output format")
        }
        
        // ミキサーに接続
        engine.connect(systemPlayer, to: mixer, format: outputFormat)
        engine.connect(micPlayer, to: mixer, format: outputFormat)
        
        // 出力ファイルを作成
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
        
        // 簡易ミキシング: システム音声ファイルをベースに、マイク音声を追加
        try await performSimpleMixing(
            systemFile: systemFile,
            micFile: micFile,
            outputFile: outputFile,
            outputFormat: outputFormat
        )
        
        logger.info("Audio mixing completed")
    }
    
    private func performSimpleMixing(
        systemFile: AVAudioFile,
        micFile: AVAudioFile,
        outputFile: AVAudioFile,
        outputFormat: AVAudioFormat
    ) async throws {
        
        let maxFrames = max(systemFile.length, micFile.length)
        let bufferSize: AVAudioFrameCount = 4096
        
        // フォーマット互換性チェック
        guard AVAudioConverter(from: systemFile.processingFormat, to: outputFormat) != nil else {
            throw RecordingError.setupFailed("Failed to create system audio converter")
        }
        
        guard AVAudioConverter(from: micFile.processingFormat, to: outputFormat) != nil else {
            throw RecordingError.setupFailed("Failed to create microphone converter")
        }
        
        var framesProcessed: AVAudioFramePosition = 0
        
        while framesProcessed < maxFrames {
            let framesToProcess = min(bufferSize, AVAudioFrameCount(maxFrames - framesProcessed))
            
            // システム音声バッファ
            let systemBuffer = AVAudioPCMBuffer(pcmFormat: systemFile.processingFormat, frameCapacity: framesToProcess) ?? AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToProcess)!
            let micBuffer = AVAudioPCMBuffer(pcmFormat: micFile.processingFormat, frameCapacity: framesToProcess) ?? AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToProcess)!
            
            // 出力バッファ
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToProcess) else {
                throw RecordingError.setupFailed("Failed to create output buffer")
            }
            
            // ファイルから読み込み
            systemFile.framePosition = framesProcessed
            micFile.framePosition = framesProcessed
            
            var actualSystemFrames: AVAudioFrameCount = 0
            var actualMicFrames: AVAudioFrameCount = 0
            
            if framesProcessed < systemFile.length {
                try systemFile.read(into: systemBuffer, frameCount: framesToProcess)
                actualSystemFrames = systemBuffer.frameLength
            }
            
            if framesProcessed < micFile.length {
                try micFile.read(into: micBuffer, frameCount: framesToProcess)
                actualMicFrames = micBuffer.frameLength
            }
            
            // 簡易ミキシング: システム音声をベースにマイクを追加
            outputBuffer.frameLength = max(actualSystemFrames, actualMicFrames)
            
            if let systemFloatData = systemBuffer.floatChannelData,
               let micFloatData = micBuffer.floatChannelData,
               let outputFloatData = outputBuffer.floatChannelData {
                
                for channel in 0..<Int(outputFormat.channelCount) {
                    for frame in 0..<Int(outputBuffer.frameLength) {
                        var mixedSample: Float = 0.0
                        
                        // システム音声（75%の音量）
                        if channel < systemBuffer.format.channelCount && frame < actualSystemFrames {
                            mixedSample += systemFloatData[channel][frame] * 0.75
                        }
                        
                        // マイク音声（50%の音量）
                        if channel < micBuffer.format.channelCount && frame < actualMicFrames {
                            mixedSample += micFloatData[min(channel, Int(micBuffer.format.channelCount)-1)][frame] * 0.5
                        }
                        
                        // クリッピング防止
                        outputFloatData[channel][frame] = max(-1.0, min(1.0, mixedSample))
                    }
                }
            }
            
            // ファイルに書き込み
            try outputFile.write(from: outputBuffer)
            
            framesProcessed += AVAudioFramePosition(outputBuffer.frameLength)
        }
    }
    
    private func cleanupTempFiles(systemURL: URL, micURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: systemURL.path) {
                try FileManager.default.removeItem(at: systemURL)
                logger.info("Cleaned up system audio temp file")
            }
            
            if FileManager.default.fileExists(atPath: micURL.path) {
                try FileManager.default.removeItem(at: micURL)
                logger.info("Cleaned up microphone temp file")
            }
        } catch {
            logger.error("Failed to cleanup temp files: \(error)")
        }
    }
}

// MARK: - SCStreamOutput Protocol
extension SystemAudioRecorder {
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { 
            // ビデオフレームは無視
            return 
        }
        
        // 音声サンプルの受信をログ（1回のみ出力）
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        if frameCount > 0 {
            // 最初のサンプルでログ（オーディオが流れていることを確認）
            Task { @MainActor in
                if self.lastAudioLogTime == nil {
                    self.logger.info("📻 System audio capture active: \(frameCount) frames received")
                    self.lastAudioLogTime = Date()
                }
            }
        }
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // CMSampleBufferをAVAudioPCMBufferに変換（同期的に実行）
            guard let audioBuffer = self.createAudioBuffer(from: sampleBuffer) else {
                Task { @MainActor in
                    self.logger.error("Failed to create audio buffer from sample buffer")
                }
                return
            }
            
            Task { @MainActor in
                guard self.isRecording else { return }
                
                // ファイルに書き込み
                do {
                    try self.audioFile?.write(from: audioBuffer)
                } catch {
                    self.logger.error("Failed to write system audio buffer: \(error.localizedDescription)")
                }
            }
        }
    }
    
    nonisolated private func createAudioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
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