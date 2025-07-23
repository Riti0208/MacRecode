import XCTest
@testable import MacRecode

@MainActor
final class SystemAudioRecorderTests: XCTestCase {
    
    func testSystemAudioRecorderInitialization() async {
        let recorder = SystemAudioRecorder()
        XCTAssertFalse(recorder.isRecording, "新しく作成したレコーダーは録音中でないはず")
        XCTAssertNil(recorder.currentRecordingURL, "録音開始前は録音URLがnilのはず")
    }
    
    func testStartRecording() async throws {
        let recorder = SystemAudioRecorder()
        
        try await recorder.startRecording()
        
        XCTAssertTrue(recorder.isRecording, "startRecording後は録音中になるはず")
        XCTAssertNotNil(recorder.currentRecordingURL, "録音開始後は録音URLが設定されるはず")
    }
    
    func testStopRecording() async throws {
        let recorder = SystemAudioRecorder()
        
        try await recorder.startRecording()
        XCTAssertTrue(recorder.isRecording)
        
        recorder.stopRecording()
        
        XCTAssertFalse(recorder.isRecording, "stopRecording後は録音中でないはず")
    }
    
    func testRecordingPermissionCheck() async {
        let recorder = SystemAudioRecorder()
        
        let hasPermission = await recorder.checkRecordingPermission()
        
        // 権限があるかないかに関わらず、結果はBool値であることを確認
        XCTAssertTrue(hasPermission, "最小実装では常にtrueを返す")
    }
    
    // MARK: - Mixed Recording Tests
    
    func testMixedRecordingBasicFunctionality() async throws {
        let recorder = SystemAudioRecorder()
        
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        
        // When: ミックス録音を開始（最小実装）
        try await recorder.startMixedRecording()
        
        // Then: 録音状態になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.currentRecordingURL)
        
        // When: 録音を停止
        recorder.stopRecording()
        
        // Then: 録音が停止する
        XCTAssertFalse(recorder.isRecording)
    }
    
    func testAudioMixerNodeConfiguration() async throws {
        let recorder = SystemAudioRecorder()
        
        // When: ミックス録音のセットアップを実行
        try await recorder.setupMixedRecording()
        
        // Then: ミキサーノードが正しく設定されている
        XCTAssertTrue(recorder.hasMixerNodeConfigured(), "ミキサーノードが設定されていません")
        XCTAssertTrue(recorder.hasSystemAudioPlayerNodeConnected(), "システム音声プレイヤーノードが接続されていません")
        XCTAssertTrue(recorder.hasMicrophoneInputConnected(), "マイク入力が接続されていません")
    }
    
    func testSynchronizedStartMechanism() async throws {
        let recorder = SystemAudioRecorder()
        
        // When: 同期開始でミックス録音を実行
        let startTime = try await recorder.startMixedRecordingWithSync()
        
        // Then: 両方のオーディオソースが同じタイムスタンプで開始される
        XCTAssertNotNil(startTime, "開始タイムスタンプが取得できません")
        XCTAssertTrue(recorder.isSystemAudioSynchronized(), "システム音声が同期開始されていません")
        XCTAssertTrue(recorder.isMicrophoneSynchronized(), "マイクが同期開始されていません")
        
        recorder.stopRecording()
    }
    
    func testUnifiedAudioFormat() async throws {
        let recorder = SystemAudioRecorder()
        
        // Given: ミックス録音が設定済み
        try await recorder.setupMixedRecording()
        
        // When: 録音フォーマットを取得
        let recordingFormat = recorder.getMixedRecordingFormat()
        
        // Then: 44.1kHz/2chの統一フォーマット
        XCTAssertEqual(recordingFormat.sampleRate, 44100.0, "サンプルレートが44.1kHzではありません")
        XCTAssertEqual(recordingFormat.channelCount, 2, "チャンネル数が2chではありません")
        XCTAssertNotNil(recordingFormat, "録音フォーマットが設定されていません")
    }
}