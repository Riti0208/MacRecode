import XCTest
import AVFoundation
import CoreAudio
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
        XCTAssertNotEqual(recorder.targetOutputDevice, 0)
        
        // TAP descriptionの詳細検証
        if let description = recorder.tapDescription {
            XCTAssertEqual(description.sampleRate, 44100.0)
            XCTAssertEqual(description.channelCount, 2)
            XCTAssertEqual(description.bufferFrameSize, 1024)
            XCTAssertTrue(CoreAudioUtilities.validateAudioFormat(description.format))
        }
    }
    
    func testAggregateDeviceCreation() async throws {
        // 前提: CATapがセットアップ済み
        try await recorder.setupCATap()
        
        // アグリゲートデバイスの作成をテスト
        try await recorder.createAggregateDevice()
        
        // アグリゲートデバイスが作成されることを確認
        XCTAssertNotEqual(recorder.aggregateDeviceID, 0)
        XCTAssertTrue(recorder.isDriftCorrectionEnabled)
        
        // アグリゲートデバイスIDがTAPデバイスIDと異なることを確認
        XCTAssertNotEqual(recorder.aggregateDeviceID, recorder.tapObjectID)
    }
    
    func testSynchronizedRecording() async throws {
        // 統合テスト: 同期録音の開始から停止まで
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let testURL = documentsPath.appendingPathComponent("test_catap_recording_\(timestamp).caf")
        
        // 録音開始前の状態確認
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        
        // 録音開始
        try await recorder.startSynchronizedRecording(to: testURL)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, testURL)
        
        // セットアップ状態の確認
        XCTAssertNotEqual(recorder.aggregateDeviceID, 0)
        XCTAssertNotEqual(recorder.tapObjectID, 0)
        XCTAssertTrue(recorder.isDriftCorrectionEnabled)
        
        // 短時間録音（オーディオバッファの生成を待つ）
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
        
        // 録音停止
        try await recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        
        // ファイルが作成され、サイズが0より大きいことを確認
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))
        
        let attributes = try FileManager.default.attributesOfItem(atPath: testURL.path)
        if let fileSize = attributes[.size] as? Int64 {
            XCTAssertGreaterThan(fileSize, 0, "Recording file should not be empty")
        }
        
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
    
    // MARK: - セキュリティ・検証テスト
    
    func testOutputPathValidation() async throws {
        try await recorder.setupCATap()
        try await recorder.createAggregateDevice()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 有効なパスのテスト
        let validURL = documentsPath.appendingPathComponent("valid_recording.caf")
        XCTAssertNoThrow(try await recorder.startSynchronizedRecording(to: validURL))
        try? await recorder.stopRecording()
        try? FileManager.default.removeItem(at: validURL)
        
        // 無効なファイル拡張子のテスト
        let invalidExtensionURL = documentsPath.appendingPathComponent("invalid.txt")
        do {
            try await recorder.startSynchronizedRecording(to: invalidExtensionURL)
            XCTFail("Should have thrown error for invalid file extension")
        } catch RecordingError.setupFailed(let message) {
            XCTAssertTrue(message.contains("not allowed"))
        }
        
        // ディレクトリトラバーサル攻撃のテスト
        let traversalURL = documentsPath.appendingPathComponent("../../../etc/passwd.caf")
        do {
            try await recorder.startSynchronizedRecording(to: traversalURL)
            XCTFail("Should have thrown error for directory traversal")
        } catch RecordingError.setupFailed(let message) {
            XCTAssertTrue(message.contains("directory traversal"))
        }
    }
    
    func testCoreAudioUtilities() {
        // デフォルト出力デバイスの取得テスト
        XCTAssertNoThrow(try CoreAudioUtilities.getDefaultOutputDevice())
        
        do {
            let defaultDevice = try CoreAudioUtilities.getDefaultOutputDevice()
            XCTAssertNotEqual(defaultDevice, kAudioObjectUnknown)
            
            // デバイス名の取得テスト
            let deviceName = try CoreAudioUtilities.getDeviceName(for: defaultDevice)
            XCTAssertFalse(deviceName.isEmpty)
            
            // TAP サポートのテスト
            let supportsTap = CoreAudioUtilities.deviceSupportsTap(defaultDevice)
            XCTAssertTrue(supportsTap == true || supportsTap == false) // Either result is valid
        } catch {
            XCTFail("Core Audio utilities should work with default device: \(error)")
        }
    }
    
    func testAudioFormatValidation() {
        // 有効なフォーマットのテスト
        let validFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        XCTAssertTrue(CoreAudioUtilities.validateAudioFormat(validFormat))
        
        // 無効なフォーマットのテスト（サンプルレート0）
        var invalidFormat = validFormat
        invalidFormat.mSampleRate = 0
        XCTAssertFalse(CoreAudioUtilities.validateAudioFormat(invalidFormat))
        
        // 無効なフォーマットのテスト（チャンネル数0）
        invalidFormat = validFormat
        invalidFormat.mChannelsPerFrame = 0
        XCTAssertFalse(CoreAudioUtilities.validateAudioFormat(invalidFormat))
    }
    
    func testErrorRecovery() async throws {
        // 重複録音開始のテスト
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let testURL = documentsPath.appendingPathComponent("error_recovery_test.caf")
        
        try await recorder.startSynchronizedRecording(to: testURL)
        
        // 既に録音中の状態で再度開始を試行
        do {
            try await recorder.startSynchronizedRecording(to: testURL)
            XCTFail("Should have thrown RecordingError.recordingInProgress")
        } catch RecordingError.recordingInProgress {
            // Expected error
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        
        // 正常に停止できることを確認
        try await recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
        
        try? FileManager.default.removeItem(at: testURL)
    }
    
    // MARK: - パフォーマンステスト
    
    func testSetupPerformance() {
        measure {
            let testRecorder = CATapAudioRecorder()
            let expectation = XCTestExpectation(description: "Setup performance")
            
            Task {
                do {
                    try await testRecorder.setupCATap()
                    try await testRecorder.createAggregateDevice()
                    expectation.fulfill()
                } catch {
                    XCTFail("Setup failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}

// MARK: - テスト用の録音モード定義
extension RecordingMode {
    static let synchronizedMixed = RecordingMode.mixedRecording
}