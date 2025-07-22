import XCTest
import ScreenCaptureKit
import AVFoundation
@testable import MacRecode

final class SystemAudioRecorderTests: XCTestCase {
    var recorder: SystemAudioRecorder!
    
    override func setUp() {
        super.setUp()
        recorder = SystemAudioRecorder()
    }
    
    override func tearDown() {
        recorder = nil
        super.tearDown()
    }
    
    // Test 1: システム音声録音が可能であることをテスト
    func testSystemAudioRecordingCapability() async throws {
        // Given: システム音声録音が可能な状態
        let canRecord = await recorder.checkSystemAudioPermission()
        XCTAssertTrue(canRecord, "システム音声録音の権限が必要です")
    }
    
    // Test 2: システム音声録音の開始と停止
    func testSystemAudioRecordingStartStop() async throws {
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        
        // When: システム音声録音を開始
        try await recorder.startSystemAudioRecording()
        
        // Then: 録音状態になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.currentRecordingURL)
        
        // When: 録音を停止
        recorder.stopRecording()
        
        // Then: 録音が停止する
        XCTAssertFalse(recorder.isRecording)
    }
    
    // Test 3: ScreenCaptureKitの音声キャプチャ設定
    func testScreenCaptureAudioConfiguration() async throws {
        // Given: ScreenCaptureKitが利用可能
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        XCTAssertFalse(content.displays.isEmpty, "ディスプレイが見つかりません")
        
        // When: 音声キャプチャの設定を確認
        let hasAudioCapture = recorder.supportsSystemAudioCapture()
        
        // Then: システム音声キャプチャがサポートされている
        XCTAssertTrue(hasAudioCapture, "システム音声キャプチャがサポートされていません")
    }
    
    // Test 4: 音声ファイルの保存
    func testAudioFileSaving() async throws {
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)
        
        // When: 短時間の録音を実行
        try await recorder.startSystemAudioRecording()
        
        // 0.5秒待機
        try await Task.sleep(nanoseconds: 500_000_000)
        
        recorder.stopRecording()
        
        // Then: ファイルが作成されている
        guard let recordingURL = recorder.currentRecordingURL else {
            XCTFail("録音URLが設定されていません")
            return
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingURL.path), "録音ファイルが作成されていません")
        
        // ファイルサイズが0より大きい
        let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "録音ファイルにデータが含まれていません")
    }
    
    // MARK: - Microphone Recording Tests
    
    // Test 5: マイクのみ録音機能のテスト
    func testMicrophoneOnlyRecording() async throws {
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        
        // When: マイクのみ録音を開始（この機能はまだ実装されていない）
        try await recorder.startMicrophoneRecording()
        
        // Then: 録音状態になる
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.currentRecordingURL)
        
        // When: 録音を停止
        recorder.stopRecording()
        
        // Then: 録音が停止する
        XCTAssertFalse(recorder.isRecording)
    }
    
    // Test 6: 録音モードの設定テスト
    func testRecordingModeSettings() {
        // Given: 録音していない状態
        XCTAssertFalse(recorder.isRecording)
        
        // When/Then: 録音モードを設定（この機能はまだ実装されていない）
        recorder.setRecordingMode(.microphoneOnly)
        XCTAssertEqual(recorder.recordingMode, .microphoneOnly)
        
        recorder.setRecordingMode(.systemAudioOnly)
        XCTAssertEqual(recorder.recordingMode, .systemAudioOnly)
        
        recorder.setRecordingMode(.mixedRecording)
        XCTAssertEqual(recorder.recordingMode, .mixedRecording)
    }
    
    // Test 7: マイク権限チェックテスト
    func testMicrophonePermissionCheck() async {
        // When: マイク権限をチェック（この機能はまだ実装されていない）
        let hasPermission = await recorder.checkMicrophonePermission()
        
        // Then: 権限状態が取得できる
        XCTAssertNotNil(hasPermission, "マイク権限の状態を取得できませんでした")
    }
}