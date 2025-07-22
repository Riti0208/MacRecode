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
}