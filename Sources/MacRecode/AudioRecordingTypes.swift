import Foundation
import CoreAudio

// MARK: - Recording Mode Enumeration

public enum RecordingMode {
    case microphoneOnly
    case systemAudioOnly
    case mixedRecording
    case catapSynchronized // CATap API による同期録音
}

// MARK: - Recording Error Enumeration

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

// MARK: - UI統合用の列挙型

public enum RecorderType {
    case systemAudio
    case catap
}

public enum PermissionStatus {
    case unknown
    case granted
    case denied
}

// MARK: - CATap Feature Support Structures

public struct CATapFeatures {
    public let supportsSystemAudioTap: Bool
    public let supportsHardwareSync: Bool
    public let supportsRealtimeProcessing: Bool
    
    public init(supportsSystemAudioTap: Bool, supportsHardwareSync: Bool, supportsRealtimeProcessing: Bool) {
        self.supportsSystemAudioTap = supportsSystemAudioTap
        self.supportsHardwareSync = supportsHardwareSync
        self.supportsRealtimeProcessing = supportsRealtimeProcessing
    }
}

public struct AggregateDeviceInfo {
    public let includesSystemAudio: Bool
    public let includesMicrophone: Bool
    public let hasHardwareSync: Bool
    public let clockSource: AudioObjectID?
    
    public init(includesSystemAudio: Bool, includesMicrophone: Bool, hasHardwareSync: Bool, clockSource: AudioObjectID?) {
        self.includesSystemAudio = includesSystemAudio
        self.includesMicrophone = includesMicrophone
        self.hasHardwareSync = hasHardwareSync
        self.clockSource = clockSource
    }
}

public struct CaptureStatistics {
    public let hasSystemAudioSamples: Bool
    public let hasMicrophoneSamples: Bool
    public let isSynchronized: Bool
    public let sampleCount: Int
    public let syncAccuracy: Double
    
    public init(hasSystemAudioSamples: Bool, hasMicrophoneSamples: Bool, isSynchronized: Bool, sampleCount: Int, syncAccuracy: Double) {
        self.hasSystemAudioSamples = hasSystemAudioSamples
        self.hasMicrophoneSamples = hasMicrophoneSamples
        self.isSynchronized = isSynchronized
        self.sampleCount = sampleCount
        self.syncAccuracy = syncAccuracy
    }
}

public struct DriftCorrectionInfo {
    public let algorithm: String?
    public let isActive: Bool
    public let correctionPrecision: Double
    
    public init(algorithm: String?, isActive: Bool, correctionPrecision: Double) {
        self.algorithm = algorithm
        self.isActive = isActive
        self.correctionPrecision = correctionPrecision
    }
}

public struct CoreAudioHALStatus {
    public let isIntegrated: Bool
    public let halDeviceID: AudioObjectID?
    public let supportsLowLatency: Bool
    public let supportsRealtimeProcessing: Bool
    
    public init(isIntegrated: Bool, halDeviceID: AudioObjectID?, supportsLowLatency: Bool, supportsRealtimeProcessing: Bool) {
        self.isIntegrated = isIntegrated
        self.halDeviceID = halDeviceID
        self.supportsLowLatency = supportsLowLatency
        self.supportsRealtimeProcessing = supportsRealtimeProcessing
    }
}