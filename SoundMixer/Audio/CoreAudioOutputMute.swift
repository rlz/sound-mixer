import CoreAudio
import Foundation

enum CoreAudioOutputMute {
    struct Control {
        let address: AudioObjectPropertyAddress
        let value: Bool
        let writable: Bool
    }

    static func read(deviceID: AudioDeviceID) -> Control? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var rawValue = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rawValue) == noErr else { return nil }
        var settable = DarwinBoolean(false)
        let writable = AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
        return Control(address: address, value: rawValue != 0, writable: writable)
    }

    static func write(_ muted: Bool, deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) throws {
        var address = address
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
        guard status == noErr else { throw VolumeError.audioStatus(status) }
    }
}
