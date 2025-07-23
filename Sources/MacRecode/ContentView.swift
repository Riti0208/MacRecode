import SwiftUI
import UniformTypeIdentifiers

// RecorderType and PermissionStatus are now defined in AudioRecordingTypes.swift

struct ContentView: View {
    @StateObject private var audioRecorder = SystemAudioRecorder()
    @StateObject private var catapRecorder = CATapAudioRecorder()
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedRecordingMode: RecordingMode = .systemAudioOnly
    
    // CATap関連の状態
    @State private var catapPermissionStatus: PermissionStatus = .unknown
    
    var body: some View {
        VStack(spacing: 30) {
            Text("MacRecode")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // 録音モード選択
            VStack(spacing: 10) {
                Text("録音モード")
                    .font(.headline)
                
                Picker("録音モード", selection: $selectedRecordingMode) {
                    Text("システム音声のみ").tag(RecordingMode.systemAudioOnly)
                    Text("CATap同期録音").tag(RecordingMode.catapSynchronized)
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // 状態表示
            VStack(spacing: 15) {
                if audioRecorder.isRecording || catapRecorder.isRecording {
                    HStack {
                        Circle()
                            .fill(catapRecorder.isRecording ? Color.blue : Color.red)
                            .frame(width: 12, height: 12)
                        
                        Text(catapRecorder.isRecording ? "CATap録音中..." : "録音中...")
                            .font(.headline)
                            .foregroundColor(catapRecorder.isRecording ? .blue : .red)
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
                                    try await catapRecorder.stopRecording()
                                } else {
                                    audioRecorder.stopRecording()
                                }
                            } catch {
                                errorMessage = "録音停止エラー: \(error.localizedDescription)"
                                showingError = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("録音開始") {
                        Task {
                            do {
                                if selectedRecordingMode == .catapSynchronized {
                                    try await startCATapRecording()
                                } else {
                                    try await audioRecorder.startRecording()
                                }
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .alert("エラー", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "不明なエラーが発生しました")
        }
        .onAppear {
            Task {
                await initializeCATapPermissions()
            }
        }
    }
    
    // MARK: - CATap統合メソッド
    
    private func initializeCATapPermissions() async {
        let hasPermission = await catapRecorder.checkAudioCapturePermission()
        catapPermissionStatus = hasPermission ? .granted : .denied
    }
    
    private func startCATapRecording() async throws {
        // CATapセットアップ
        try await catapRecorder.setupCATap()
        try await catapRecorder.createAggregateDevice()
        
        // 録音URL生成
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let recordingURL = documentsPath.appendingPathComponent("CATapSync_\(timestamp).caf")
        
        // 録音開始
        try await catapRecorder.startSynchronizedRecording(to: recordingURL)
    }
}

#Preview {
    ContentView()
}