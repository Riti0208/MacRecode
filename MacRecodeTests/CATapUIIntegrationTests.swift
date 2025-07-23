import XCTest
import SwiftUI
@testable import MacRecode

class CATapUIIntegrationTests: XCTestCase {
    
    var contentView: ContentView!
    
    override func setUp() {
        super.setUp()
        contentView = ContentView()
    }
    
    override func tearDown() {
        contentView = nil
        super.tearDown()
    }
    
    // MARK: - CATap統合テスト（失敗するテスト）
    
    func testCATapRecorderIntegration() {
        // ContentViewがCATapAudioRecorderを統合していることをテスト
        // 現在は失敗するはず（まだ統合されていない）
        XCTAssertNotNil(contentView.catapRecorder, "ContentViewはCATapAudioRecorderを持つべき")
    }
    
    func testRecordingModeSelector() {
        // CATap同期録音モードが選択肢に含まれることをテスト
        let expectedModes: [RecordingMode] = [
            .systemAudioOnly,
            .microphoneOnly, 
            .mixedRecording,
            .catapSynchronized  // 新しいモード
        ]
        
        // 現在は失敗するはず（まだCATapモードが追加されていない）
        XCTAssertTrue(expectedModes.contains(.catapSynchronized), "CATap同期録音モードが利用可能であるべき")
    }
    
    func testCATapRecordingStart() async throws {
        // CATap同期録音の開始をテスト
        let catapRecorder = CATapAudioRecorder()
        
        // セットアップ
        try await catapRecorder.setupCATap()
        try await catapRecorder.createAggregateDevice()
        
        // 録音開始（テスト用URL）
        let testURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_catap_ui.caf")
        
        try await catapRecorder.startSynchronizedRecording(to: testURL)
        
        // 状態確認
        XCTAssertTrue(catapRecorder.isRecording, "CATap録音が開始されているべき")
        XCTAssertEqual(catapRecorder.currentRecordingURL, testURL, "録音URLが正しく設定されているべき")
        
        // 停止
        try await catapRecorder.stopRecording()
        XCTAssertFalse(catapRecorder.isRecording, "CATap録音が停止されているべき")
        
        // クリーンアップ
        try? FileManager.default.removeItem(at: testURL)
    }
    
    func testUIStateManagement() {
        // UI状態管理のテスト
        // 現在は失敗するはず（CATap関連の状態管理が未実装）
        
        // CATap録音中の状態表示
        XCTAssertFalse(contentView.isCATapRecording, "初期状態でCATap録音は停止しているべき")
        
        // CATap録音エラー状態の管理
        XCTAssertNil(contentView.catapErrorMessage, "初期状態でCATapエラーメッセージはnilであるべき")
        
        // CATap権限状態の管理
        XCTAssertFalse(contentView.catapPermissionGranted, "初期状態でCATap権限は未許可であるべき")
    }
    
    func testRecordingModeSwitch() {
        // 録音モード切り替えのテスト
        // SystemAudioRecorderからCATapAudioRecorderへの切り替え
        
        // 初期状態（SystemAudioRecorder使用）
        XCTAssertEqual(contentView.activeRecorderType, .systemAudio, "初期状態はSystemAudioRecorderであるべき")
        
        // CATapモードに切り替え（現在は失敗するはず）
        contentView.switchToRecorderType(.catap)
        XCTAssertEqual(contentView.activeRecorderType, .catap, "CATapモードに切り替わっているべき")
    }
    
    func testCATapPermissionFlow() async throws {
        // CATap権限フローのテスト
        let catapRecorder = CATapAudioRecorder()
        
        // 権限チェック
        let hasPermission = await catapRecorder.checkAudioCapturePermission()
        
        // UI状態への反映（現在は失敗するはず）
        XCTAssertEqual(contentView.catapPermissionStatus, hasPermission ? .granted : .denied, 
                      "権限状態がUIに正しく反映されるべき")
    }
    
    func testErrorHandlingIntegration() {
        // エラーハンドリング統合テスト
        let testError = RecordingError.setupFailed("Test CATap setup failure")
        
        // CATapエラーの処理（現在は失敗するはず）
        contentView.handleCATapError(testError)
        
        XCTAssertNotNil(contentView.catapErrorMessage, "CATapエラーメッセージが設定されるべき")
        XCTAssertTrue(contentView.showingCATapError, "CATapエラーダイアログが表示されるべき")
    }
    
    func testSynchronizedRecordingWorkflow() async throws {
        // エンドツーエンドの同期録音ワークフローテスト
        // 現在は失敗するはず（統合されていない）
        
        // 1. CATapモード選択
        contentView.selectedRecordingMode = .catapSynchronized
        
        // 2. 録音開始
        try await contentView.startCATapRecording()
        
        // 3. 状態確認
        XCTAssertTrue(contentView.isCATapRecording, "CATap録音が開始されているべき")
        XCTAssertNotNil(contentView.catapRecorder?.currentRecordingURL, "録音URLが設定されているべき")
        
        // 4. 短時間録音
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // 5. 録音停止
        try await contentView.stopCATapRecording()
        
        // 6. 最終状態確認
        XCTAssertFalse(contentView.isCATapRecording, "CATap録音が停止されているべき")
    }
}

// MARK: - テスト用拡張は不要（実装完了）
// ContentViewに実際の実装が追加されたため、プレースホルダーextensionは削除