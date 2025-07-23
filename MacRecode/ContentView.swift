import SwiftUI
import UniformTypeIdentifiers

// MARK: - UI統合用の列挙型
enum RecorderType {
    case systemAudio
    case catap
}

enum PermissionStatus {
    case unknown
    case granted
    case denied
}

struct ContentView: View {
    @StateObject private var audioRecorder = SystemAudioRecorder()
    @StateObject private var catapRecorder = CATapAudioRecorder()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var successMessage: String?
    @State private var showingSuccess = false
    @State private var showingSaveDialog = false
    @State private var tempRecordingURL: URL?
    @State private var isStartingRecording = false
    @State private var selectedRecordingMode: RecordingMode = .systemAudioOnly
    
    // CATap関連の状態
    @State private var catapErrorMessage: String?
    @State private var showingCATapError = false
    @State private var catapPermissionStatus: PermissionStatus = .unknown
    
    // MARK: - 計算プロパティ
    var activeRecorderType: RecorderType {
        selectedRecordingMode == .catapSynchronized ? .catap : .systemAudio
    }
    
    var isCATapRecording: Bool {
        catapRecorder.isRecording
    }
    
    var catapPermissionGranted: Bool {
        catapPermissionStatus == .granted
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // タイトル
            Text("MacRecode")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // 録音モード選択
            VStack(spacing: 10) {
                Text("録音モード")
                    .font(.headline)
                
                Picker("録音モード", selection: $selectedRecordingMode) {
                    Text("システム音声のみ").tag(RecordingMode.systemAudioOnly)
                    Text("マイクのみ").tag(RecordingMode.microphoneOnly)
                    Text("システム音声+マイク").tag(RecordingMode.mixedRecording) // 実装済みのため有効化
                    Text("CATap同期録音").tag(RecordingMode.catapSynchronized) // CATap API統合
                }
                .pickerStyle(MenuPickerStyle())
                .disabled(audioRecorder.isRecording || catapRecorder.isRecording || isStartingRecording)
                .onChange(of: selectedRecordingMode) { newMode in
                    audioRecorder.setRecordingMode(newMode)
                }
            }
            
            // 状態表示
            VStack(spacing: 15) {
                if audioRecorder.isRecording || catapRecorder.isRecording {
                    HStack {
                        Circle()
                            .fill(catapRecorder.isRecording ? Color.blue : Color.red)
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: audioRecorder.isRecording || catapRecorder.isRecording)
                        
                        Text(catapRecorder.isRecording ? "CATap録音中..." : "録音中...")
                            .font(.headline)
                            .foregroundColor(catapRecorder.isRecording ? .blue : .red)
                    }
                } else if isStartingRecording {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("開始中...")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("準備完了")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            
            // コントロールボタン
            HStack(spacing: 20) {
                if audioRecorder.isRecording || catapRecorder.isRecording {
                    Button("録音停止") {
                        Task {
                            do {
                                if catapRecorder.isRecording {
                                    // CATap録音停止
                                    try await stopCATapRecording()
                                } else if audioRecorder.recordingMode == .mixedRecording {
                                    // ミックス録音停止
                                    tempRecordingURL = audioRecorder.currentRecordingURL
                                    try await audioRecorder.stopMixedRecording()
                                } else {
                                    // 通常録音停止
                                    tempRecordingURL = audioRecorder.currentRecordingURL
                                    audioRecorder.stopRecording()
                                }
                                showingSaveDialog = true
                            } catch {
                                if catapRecorder.isRecording {
                                    handleCATapError(error)
                                } else {
                                    errorMessage = "録音停止エラー: \(error.localizedDescription)"
                                    showingError = true
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                } else {
                    Button("録音開始") {
                        isStartingRecording = true
                        Task {
                            do {
                                if selectedRecordingMode == .catapSynchronized {
                                    // CATap録音
                                    try await startCATapRecording()
                                } else {
                                    // 従来の録音
                                    try await audioRecorder.startRecordingWithMode()
                                }
                                errorMessage = nil
                                catapErrorMessage = nil
                            } catch {
                                if selectedRecordingMode == .catapSynchronized {
                                    handleCATapError(error)
                                } else {
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                            isStartingRecording = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(isStartingRecording || audioRecorder.isRecording || catapRecorder.isRecording || 
                              (selectedRecordingMode == .catapSynchronized && catapPermissionStatus != .granted))
                }
            }
            
            // 説明文
            VStack(spacing: 5) {
                switch selectedRecordingMode {
                case .systemAudioOnly:
                    Text("システム全体の音声を録音します。\n初回起動時は「画面収録」の権限許可が必要です。")
                case .microphoneOnly:
                    Text("マイクからの音声のみを録音します。\n初回起動時はマイクアクセスの権限許可が必要です。")
                case .mixedRecording:
                    Text("システム音声とマイクを同時録音します。\nヘッドフォン/イヤホンの使用を強く推奨します。")
                        .foregroundColor(.primary)
                case .catapSynchronized:
                    Text("CATap APIによる高精度同期録音です。\nハードウェアレベルでの同期とドリフト補正を提供します。")
                        .foregroundColor(.blue)
                }
                
                if selectedRecordingMode == .mixedRecording {
                    Text("⚠️ エコー防止のため、必ずヘッドフォンをご使用ください")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                } else if selectedRecordingMode == .catapSynchronized {
                    VStack(spacing: 4) {
                        Text("📡 macOS 14.4+が必要です。ハードウェア同期により高品質録音を実現します")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                        
                        // 権限状態表示
                        HStack {
                            switch catapPermissionStatus {
                            case .granted:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("CATap権限: 許可済み")
                                    .foregroundColor(.green)
                            case .denied:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("CATap権限: 未許可")
                                    .foregroundColor(.red)
                            case .unknown:
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("CATap権限: 確認中...")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(.caption2)
                    }
                }
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .fileExporter(
            isPresented: $showingSaveDialog,
            document: AudioFileDocument(url: tempRecordingURL),
            contentType: UTType(filenameExtension: "caf") ?? .audio,
            defaultFilename: generateDefaultFilename()
        ) { result in
            switch result {
            case .success(let savedURL):
                if let tempURL = tempRecordingURL {
                    // 元ファイルの存在確認
                    guard FileManager.default.fileExists(atPath: tempURL.path) else {
                        DispatchQueue.main.async {
                            errorMessage = "録音ファイルが見つかりません"
                            showingError = true
                        }
                        tempRecordingURL = nil
                        return
                    }
                    
                    do {
                        // セキュリティスコープ付きリソースアクセス
                        let didStartAccessing = savedURL.startAccessingSecurityScopedResource()
                        defer { 
                            if didStartAccessing {
                                savedURL.stopAccessingSecurityScopedResource()
                            }
                        }
                        
                        // 既存ファイルがある場合は削除してから移動
                        if FileManager.default.fileExists(atPath: savedURL.path) {
                            try FileManager.default.removeItem(at: savedURL)
                        }
                        
                        // ファイルを移動ではなくコピーして、元ファイルは保持
                        try FileManager.default.copyItem(at: tempURL, to: savedURL)
                        
                        DispatchQueue.main.async {
                            // 成功通知を表示
                            successMessage = "録音ファイルを保存しました: \(savedURL.lastPathComponent)"
                            showingSuccess = true
                        }
                        
                        // 元ファイルをクリーンアップ
                        try? FileManager.default.removeItem(at: tempURL)
                        
                    } catch {
                        DispatchQueue.main.async {
                            errorMessage = "ファイルの保存に失敗しました: \(error.localizedDescription)"
                            showingError = true
                        }
                    }
                    tempRecordingURL = nil
                } else {
                    DispatchQueue.main.async {
                        errorMessage = "録音ファイルのURLが無効です"
                        showingError = true
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    errorMessage = "ファイルエクスポートエラー: \(error.localizedDescription)"
                    showingError = true
                }
                tempRecordingURL = nil
            }
        }
        .alert("エラー", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "不明なエラーが発生しました")
        }
        .alert("完了", isPresented: $showingSuccess) {
            Button("OK") { }
        } message: {
            Text(successMessage ?? "")
        }
        .alert("CATapエラー", isPresented: $showingCATapError) {
            Button("OK") { }
        } message: {
            Text(catapErrorMessage ?? "CATap録音でエラーが発生しました")
        }
        .onAppear {
            Task {
                await initializeCATapPermissions()
            }
        }
    }
    
    // MARK: - CATap統合メソッド
    
    private func initializeCATapPermissions() async {
        // CATap権限の初期チェック
        let hasPermission = await catapRecorder.checkAudioCapturePermission()
        catapPermissionStatus = hasPermission ? .granted : .denied
    }
    
    func switchToRecorderType(_ type: RecorderType) {
        // 録音中でなければレコーダータイプを切り替え
        if !audioRecorder.isRecording && !catapRecorder.isRecording {
            selectedRecordingMode = type == .catap ? .catapSynchronized : .systemAudioOnly
        }
    }
    
    func handleCATapError(_ error: Error) {
        // より詳細なエラーメッセージを生成
        if let recordingError = error as? RecordingError {
            switch recordingError {
            case .permissionDenied(let details):
                catapErrorMessage = "CATap権限エラー: \(details)\n\nシステム環境設定でオーディオ録音権限を許可してください。"
            case .setupFailed(let details):
                catapErrorMessage = "CATapセットアップエラー: \(details)\n\nmacOS 14.4以降が必要です。"
            case .recordingInProgress:
                catapErrorMessage = "録音が既に進行中です。"
            default:
                catapErrorMessage = "CATapエラー: \(error.localizedDescription)"
            }
        } else {
            catapErrorMessage = "予期しないCATapエラー: \(error.localizedDescription)"
        }
        showingCATapError = true
    }
    
    func startCATapRecording() async throws {
        guard !catapRecorder.isRecording else {
            throw RecordingError.recordingInProgress
        }
        
        // 権限再確認
        if catapPermissionStatus != .granted {
            let hasPermission = await catapRecorder.checkAudioCapturePermission()
            catapPermissionStatus = hasPermission ? .granted : .denied
            
            guard hasPermission else {
                throw RecordingError.permissionDenied("CATap API requires audio capture permission")
            }
        }
        
        // CATapセットアップ（段階的にセットアップ）
        do {
            try await catapRecorder.setupCATap()
        } catch {
            throw RecordingError.setupFailed("CATap initialization failed: \(error.localizedDescription)")
        }
        
        do {
            try await catapRecorder.createAggregateDevice()
        } catch {
            throw RecordingError.setupFailed("Aggregate device creation failed: \(error.localizedDescription)")
        }
        
        // 録音URL生成（より説明的なファイル名）
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let recordingURL = documentsPath.appendingPathComponent("CATapSync_\(timestamp).caf")
        
        // 録音開始
        do {
            try await catapRecorder.startSynchronizedRecording(to: recordingURL)
        } catch {
            throw RecordingError.setupFailed("Synchronized recording start failed: \(error.localizedDescription)")
        }
    }
    
    func stopCATapRecording() async throws {
        guard catapRecorder.isRecording else { return }
        
        tempRecordingURL = catapRecorder.currentRecordingURL
        try await catapRecorder.stopRecording()
    }
    
    // ファイル名生成のヘルパーメソッド
    private func generateDefaultFilename() -> String {
        if let tempURL = tempRecordingURL {
            return tempURL.deletingPathExtension().lastPathComponent
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            
            switch selectedRecordingMode {
            case .systemAudioOnly:
                return "SystemAudio_\(timestamp)"
            case .microphoneOnly:
                return "Microphone_\(timestamp)"
            case .mixedRecording:
                return "Mixed_\(timestamp)"
            case .catapSynchronized:
                return "CATapSync_\(timestamp)"
            }
        }
    }
}

// DateFormatter extension for filename formatting
extension DateFormatter {
    static let yyyyMMdd_HHmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

// AudioFileDocument for file export
struct AudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] = [UTType(filenameExtension: "caf") ?? .audio]
    
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        // This won't be used for export-only documents
        self.url = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        do {
            let data = try Data(contentsOf: url)
            return FileWrapper(regularFileWithContents: data)
        } catch {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

#Preview {
    ContentView()
}