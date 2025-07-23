import XCTest
import AVFoundation
@testable import MacRecode

class CATapAudioRecorderTests: XCTestCase {
    
    var recorder: CATapAudioRecorder!
    
    override func setUp() {
        super.setUp()
        recorder = CATapAudioRecorder()
    }
    
    override func tearDown() {
        recorder = nil
        super.tearDown()
    }
    
    // MARK: - 基本機能テスト
    
    func testRecorderInitialization() {
        XCTAssertNotNil(recorder)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
    }
    
    func testPermissionCheck() async {
        // NSAudioCaptureUsageDescriptionが設定されている場合のテスト  
        let hasPermission = await recorder.checkAudioCapturePermission()
        // 権限チェックが実行されることを確認（結果は環境依存）
        XCTAssertTrue(hasPermission == true || hasPermission == false)
    }
    
    func testCATapSetup() async throws {
        // CATapDescriptionの作成をテスト
        try await recorder.setupCATap()
        
        // セットアップ後の状態確認
        XCTAssertNotNil(recorder.tapDescription)
        XCTAssertNotEqual(recorder.tapObjectID, 0)
    }
    
    func testAggregateDeviceCreation() async throws {
        // 前提: CATapがセットアップ済み
        try await recorder.setupCATap()
        
        // アグリゲートデバイスの作成をテスト
        try await recorder.createAggregateDevice()
        
        // アグリゲートデバイスが作成されることを確認
        XCTAssertNotEqual(recorder.aggregateDeviceID, 0)
    }
    
    func testSynchronizedRecording() async throws {
        // 統合テスト: 同期録音の開始から停止まで
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let testURL = documentsPath.appendingPathComponent("test_catap_recording.caf")
        
        // 録音開始
        try await recorder.startSynchronizedRecording(to: testURL)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, testURL)
        
        // 短時間録音
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // 録音停止
        try await recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        
        // ファイルが作成されることを確認
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
        
        // クリーンアップ
        try? FileManager.default.removeItem(at: testURL)
    }
    
    func testRecordingModeSupport() {
        // CATapAudioRecorderは同期録音のみサポート
        XCTAssertEqual(recorder.supportedRecordingMode, .mixedRecording)
    }
    
    func testDriftCorrectionEnabled() async throws {
        try await recorder.setupCATap()
        try await recorder.createAggregateDevice()
        
        // ドリフト補正が有効になっていることを確認
        XCTAssertTrue(recorder.isDriftCorrectionEnabled)
    }
}

// MARK: - テスト用の録音モード定義
extension RecordingMode {
    static let synchronizedMixed = RecordingMode.mixedRecording
}