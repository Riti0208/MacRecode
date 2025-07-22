import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioRecorder = SystemAudioRecorder()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var successMessage: String?
    @State private var showingSuccess = false
    @State private var showingSaveDialog = false
    @State private var tempRecordingURL: URL?
    @State private var isStartingRecording = false
    @State private var selectedRecordingMode: RecordingMode = .systemAudioOnly
    
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
                }
                .pickerStyle(SegmentedPickerStyle())
                .disabled(audioRecorder.isRecording || isStartingRecording)
                .onChange(of: selectedRecordingMode) { newMode in
                    audioRecorder.setRecordingMode(newMode)
                }
            }
            
            // 状態表示
            VStack(spacing: 15) {
                if audioRecorder.isRecording {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .animation(.easeInOut(duration: 1).repeatForever(), value: audioRecorder.isRecording)
                        
                        Text("録音中...")
                            .font(.headline)
                            .foregroundColor(.red)
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
                if audioRecorder.isRecording {
                    Button("録音停止") {
                        tempRecordingURL = audioRecorder.currentRecordingURL
                        audioRecorder.stopRecording()
                        showingSaveDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                } else {
                    Button("録音開始") {
                        isStartingRecording = true
                        Task {
                            do {
                                // 新しい統一インターフェースを使用
                                try await audioRecorder.startRecordingWithMode()
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                            isStartingRecording = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(isStartingRecording)
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
                }
                
                if selectedRecordingMode == .mixedRecording {
                    Text("⚠️ エコー防止のため、必ずヘッドフォンをご使用ください")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
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
            defaultFilename: tempRecordingURL?.deletingPathExtension().lastPathComponent ?? "SystemAudio_\(DateFormatter.yyyyMMdd_HHmmss.string(from: Date()))"
        ) { result in
            switch result {
            case .success(let savedURL):
                if let tempURL = tempRecordingURL {
                    do {
                        // セキュリティスコープ付きリソースアクセス
                        let _ = savedURL.startAccessingSecurityScopedResource()
                        defer { savedURL.stopAccessingSecurityScopedResource() }
                        
                        // 既存ファイルがある場合は削除してから移動
                        if FileManager.default.fileExists(atPath: savedURL.path) {
                            try FileManager.default.removeItem(at: savedURL)
                        }
                        
                        try FileManager.default.moveItem(at: tempURL, to: savedURL)
                        
                        DispatchQueue.main.async {
                            // 成功通知を表示
                            successMessage = "録音ファイルを保存しました: \(savedURL.lastPathComponent)"
                            showingSuccess = true
                        }
                    } catch {
                        errorMessage = "ファイルの保存に失敗しました: \(error.localizedDescription)"
                        showingError = true
                    }
                    tempRecordingURL = nil
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
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
        guard let url = url else {
            throw CocoaError(.fileWriteNoPermission)
        }
        
        let data = try Data(contentsOf: url)
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ContentView()
}