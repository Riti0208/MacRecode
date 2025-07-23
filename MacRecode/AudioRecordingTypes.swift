import Foundation
import CoreAudio
import AudioToolbox

// MARK: - Core Audio TAP Types

/// Core Audio TAP description structure
public struct CATapDescription {
    public let deviceID: AudioObjectID
    public let tapID: AudioObjectID
    public let sampleRate: Double
    public let channelCount: UInt32
    public let bufferFrameSize: UInt32
    public let format: AudioStreamBasicDescription
    
    public init(deviceID: AudioObjectID, 
                tapID: AudioObjectID,
                sampleRate: Double = 44100.0,
                channelCount: UInt32 = 2,
                bufferFrameSize: UInt32 = 1024) {
        self.deviceID = deviceID
        self.tapID = tapID
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bufferFrameSize = bufferFrameSize
        
        // Create standard PCM format description
        self.format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
            mBytesPerPacket: UInt32(channelCount * 2), // 16-bit samples
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channelCount * 2),
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 16,
            mReserved: 0
        )
    }
}

/// Aggregate device configuration for CATap integration
public struct AggregateDeviceConfiguration {
    public let name: String
    public let uid: String
    public let subDeviceUIDs: [String]
    public let masterSubDevice: String?
    public let driftCorrection: Bool
    
    public init(name: String,
                uid: String,
                subDeviceUIDs: [String],
                masterSubDevice: String? = nil,
                driftCorrection: Bool = true) {
        self.name = name
        self.uid = uid
        self.subDeviceUIDs = subDeviceUIDs
        self.masterSubDevice = masterSubDevice
        self.driftCorrection = driftCorrection
    }
    
    public static func catapAggregateConfig() -> AggregateDeviceConfiguration {
        let timestamp = Int(Date().timeIntervalSince1970)
        return AggregateDeviceConfiguration(
            name: "MacRecode CATap Aggregate",
            uid: "com.macrecode.catap.aggregate.\(timestamp)",
            subDeviceUIDs: [], // Will be populated dynamically
            masterSubDevice: nil,
            driftCorrection: true
        )
    }
}

/// Core Audio property helper
public struct CoreAudioProperty {
    public let selector: AudioObjectPropertySelector
    public let scope: AudioObjectPropertyScope
    public let element: AudioObjectPropertyElement
    
    public init(selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.selector = selector
        self.scope = scope
        self.element = element
    }
    
    public var address: AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }
    
    public func withAddress<T>(_ operation: (inout AudioObjectPropertyAddress) throws -> T) rethrows -> T {
        var address = self.address
        return try operation(&address)
    }
}

// MARK: - Error Types

public enum CoreAudioError: LocalizedError {
    case deviceNotFound(AudioObjectID)
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case propertyAccessFailed(OSStatus, AudioObjectPropertySelector)
    case invalidConfiguration(String)
    case hardwareNotSupported
    case tapNotSupported(AudioObjectID)
    case permissionDenied(String)
    case deviceBusy(AudioObjectID)
    case formatNotSupported(AudioStreamBasicDescription)
    case bufferSizeNotSupported(UInt32)
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let deviceID):
            return "Audio device not found: \(deviceID). Please check that the device is connected and available."
        case .tapCreationFailed(let status):
            let statusMessage = CoreAudioError.statusCodeDescription(status)
            return "TAP creation failed with status: \(status) (\(statusMessage)). This may indicate hardware limitations or system restrictions."
        case .aggregateDeviceCreationFailed(let status):
            let statusMessage = CoreAudioError.statusCodeDescription(status)
            return "Aggregate device creation failed with status: \(status) (\(statusMessage)). Check audio device compatibility."
        case .propertyAccessFailed(let status, let selector):
            let statusMessage = CoreAudioError.statusCodeDescription(status)
            let selectorName = CoreAudioError.selectorDescription(selector)
            return "Property access failed for \(selectorName) with status: \(status) (\(statusMessage)). Device may not support this property."
        case .invalidConfiguration(let details):
            return "Invalid audio configuration: \(details). Please check audio format settings."
        case .hardwareNotSupported:
            return "Hardware does not support TAP functionality. TAP requires macOS 14.4+ and compatible audio hardware."
        case .tapNotSupported(let deviceID):
            return "Device \(deviceID) does not support TAP functionality. Consider using a different audio device."
        case .permissionDenied(let details):
            return "Audio permission denied: \(details). Please grant microphone and audio capture permissions in System Settings."
        case .deviceBusy(let deviceID):
            return "Audio device \(deviceID) is currently in use by another application. Please close other audio applications and try again."
        case .formatNotSupported(let format):
            return "Audio format not supported: \(format.mSampleRate)Hz, \(format.mChannelsPerFrame)ch, \(format.mBitsPerChannel)bit. Device may not support this configuration."
        case .bufferSizeNotSupported(let bufferSize):
            return "Buffer size \(bufferSize) frames is not supported by the audio device. Try using a different buffer size (e.g., 256, 512, 1024)."
        }
    }
    
    // MARK: - Status Code Descriptions
    
    public static func statusCodeDescription(_ status: OSStatus) -> String {
        switch status {
        case noErr:
            return "No error"
        case kAudioHardwareNoError:
            return "No hardware error"
        case kAudioHardwareNotRunningError:
            return "Audio hardware not running"
        case kAudioHardwareUnknownPropertyError:
            return "Unknown audio property"
        case kAudioHardwareIllegalOperationError:
            return "Illegal audio operation"
        case kAudioHardwareBadObjectError:
            return "Bad audio object"
        case kAudioHardwareBadDeviceError:
            return "Bad audio device"
        case kAudioHardwareBadStreamError:
            return "Bad audio stream"
        case kAudioHardwareUnsupportedOperationError:
            return "Unsupported audio operation"
        case kAudioDeviceUnsupportedFormatError:
            return "Unsupported audio format"
        case kAudioDevicePermissionsError:
            return "Audio device permissions error"
        default:
            // Convert OSStatus to FourCharCode for debugging
            let fourCC = OSTypeToString(OSType(status))
            return "Unknown error (\(status), '\(fourCC)')"
        }
    }
    
    // MARK: - Property Selector Descriptions
    
    public static func selectorDescription(_ selector: AudioObjectPropertySelector) -> String {
        switch selector {
        case kAudioObjectPropertyName:
            return "Object Name"
        case kAudioObjectPropertyManufacturer:
            return "Manufacturer"
        case kAudioObjectPropertyElementName:
            return "Element Name"
        case kAudioHardwarePropertyDefaultOutputDevice:
            return "Default Output Device"
        case kAudioHardwarePropertyDefaultInputDevice:
            return "Default Input Device"
        case kAudioHardwarePropertyDevices:
            return "Audio Devices"
        case kAudioDevicePropertyStreamConfiguration:
            return "Stream Configuration"
        case kAudioDevicePropertyAvailableNominalSampleRates:
            return "Available Sample Rates"
        case kAudioDevicePropertyNominalSampleRate:
            return "Nominal Sample Rate"
        default:
            let fourCC = OSTypeToString(selector)
            return "Property '\(fourCC)' (\(selector))"
        }
    }
}

// MARK: - Helper Functions

private func OSTypeToString(_ osType: OSType) -> String {
    let bytes = [
        UInt8((osType >> 24) & 0xFF),
        UInt8((osType >> 16) & 0xFF),
        UInt8((osType >> 8) & 0xFF),
        UInt8(osType & 0xFF)
    ]
    
    // Check if all bytes are printable ASCII
    let printableBytes: [Character] = bytes.compactMap { byte in
        let scalar = UnicodeScalar(byte)
        guard (32...126).contains(byte) else {
            return nil
        }
        return Character(scalar)
    }
    
    if printableBytes.count == 4 {
        return String(printableBytes)
    } else {
        return String(format: "%08X", osType)
    }
}

// MARK: - Core Audio Utilities

public class CoreAudioUtilities {
    
    /// Get system default output device
    public static func getDefaultOutputDevice() throws -> AudioObjectID {
        var deviceID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let property = CoreAudioProperty(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let status = property.withAddress { address in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            )
        }
        
        guard status == noErr else {
            throw CoreAudioError.propertyAccessFailed(status, kAudioHardwarePropertyDefaultOutputDevice)
        }
        
        guard deviceID != kAudioObjectUnknown else {
            throw CoreAudioError.deviceNotFound(deviceID)
        }
        
        return deviceID
    }
    
    /// Get device name for given device ID
    public static func getDeviceName(for deviceID: AudioObjectID) throws -> String {
        let property = CoreAudioProperty(selector: kAudioObjectPropertyName)
        var size: UInt32 = 0
        
        // Get size
        var status = property.withAddress { address in
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &size
            )
        }
        
        guard status == noErr else {
            throw CoreAudioError.propertyAccessFailed(status, kAudioObjectPropertyName)
        }
        
        // Get name
        var name: CFString?
        status = property.withAddress { address in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &name
            )
        }
        
        guard status == noErr, let deviceName = name else {
            throw CoreAudioError.propertyAccessFailed(status, kAudioObjectPropertyName)
        }
        
        return deviceName as String
    }
    
    /// Check if device supports TAP functionality
    public static func deviceSupportsTap(_ deviceID: AudioObjectID) -> Bool {
        // In production, this would check actual TAP support via Core Audio HAL
        // For now, we assume modern output devices support TAP
        do {
            let name = try getDeviceName(for: deviceID)
            // Basic heuristic: built-in devices typically support TAP
            return name.contains("Built-in") || name.contains("Internal") || deviceID != kAudioObjectUnknown
        } catch {
            return false
        }
    }
    
    /// Validate audio format compatibility
    public static func validateAudioFormat(_ format: AudioStreamBasicDescription) -> Bool {
        // Check for supported format properties
        guard format.mFormatID == kAudioFormatLinearPCM else { return false }
        guard format.mSampleRate > 0 && format.mSampleRate <= 192000 else { return false }
        guard format.mChannelsPerFrame > 0 && format.mChannelsPerFrame <= 8 else { return false }
        guard format.mBitsPerChannel == 16 || format.mBitsPerChannel == 24 || format.mBitsPerChannel == 32 else { return false }
        
        return true
    }
}