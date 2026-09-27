import AudioToolbox
import CoreAudio
import Foundation

struct AudioDeviceSnapshot: Equatable, Sendable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isAlive: Bool
    let inputChannels: Int
    let outputChannels: Int
    let nominalSampleRate: Double
    let outputVolume: Double?
    let canSetOutputVolume: Bool
    let outputMuted: Bool?
    let canSetOutputMute: Bool

    func hasSameRouting(as other: AudioDeviceSnapshot) -> Bool {
        deviceID == other.deviceID && uid == other.uid && isAlive == other.isAlive &&
            inputChannels == other.inputChannels && outputChannels == other.outputChannels &&
            nominalSampleRate == other.nominalSampleRate
    }

    func hasSameInputRouting(as other: AudioDeviceSnapshot) -> Bool {
        deviceID == other.deviceID && uid == other.uid && isAlive == other.isAlive &&
            inputChannels == other.inputChannels && nominalSampleRate == other.nominalSampleRate
    }

    func hasSameOutputRouting(as other: AudioDeviceSnapshot) -> Bool {
        deviceID == other.deviceID && uid == other.uid && isAlive == other.isAlive &&
            outputChannels == other.outputChannels && nominalSampleRate == other.nominalSampleRate
    }
}

final class CoreAudioDeviceCatalog {
    var onChange: (([AudioDeviceSnapshot]) -> Void)?

    private struct VolumeRestoreState {
        let original: Float32?
        let lastSet: Float32?
        let selector: AudioObjectPropertySelector?
        let originalMute: Bool?
        let lastSetMute: Bool?
    }

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.core-audio-catalog")
    private var deviceListeners: [AudioDeviceID: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var latestDevices: [AudioDeviceSnapshot] = []
    private var originalVolumes: [String: VolumeRestoreState] = [:]
    private var started = false

    deinit { stop() }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.started else { return }
            started = true
            var address = Self.address(kAudioHardwarePropertyDevices)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            deviceListListener = listener
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            refresh()
        }
    }

    func stop() {
        queue.sync {
            guard started else { return }
            started = false
            restoreOutputVolumes()
            var address = Self.address(kAudioHardwarePropertyDevices)
            if let deviceListListener {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, deviceListListener)
                self.deviceListListener = nil
            }
            removeDeviceListeners()
        }
    }

    func setOutputVolume(uid: String, level: Double, completion: @escaping (Result<Double, Error>) -> Void) {
        queue.async { [weak self] in
            let result: Result<Double, Error>
            do {
                guard let self else { throw VolumeError.deviceUnavailable }
                result = try .success(setOutputVolume(uid: uid, level: level))
                refresh()
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func setOutputVolume(uid: String, level: Double) throws -> Double {
        guard started, let device = latestDevices.first(where: { $0.uid == uid }),
              device.isAlive, device.outputChannels > 0 else { throw VolumeError.deviceUnavailable }
        guard let control = CoreAudioOutputVolume.read(deviceID: device.deviceID), control.writable
        else { throw VolumeError.unsupported }

        let requested = Float32(level)
        let mute = CoreAudioOutputMute.read(deviceID: device.deviceID)
        if originalVolumes[uid] == nil {
            originalVolumes[uid] = VolumeRestoreState(
                original: control.value,
                lastSet: control.value,
                selector: control.address.mSelector,
                originalMute: mute?.value,
                lastSetMute: mute?.value
            )
        }
        try CoreAudioOutputVolume.write(requested, deviceID: device.deviceID, address: control.address)
        let readback = CoreAudioOutputVolume.read(deviceID: device.deviceID)?.value
        let actual = readback ?? requested
        let lastSet = actual == control.value && requested != control.value ? requested : actual
        if let previous = originalVolumes[uid] {
            originalVolumes[uid] = VolumeRestoreState(
                original: previous.original ?? control.value,
                lastSet: lastSet,
                selector: control.address.mSelector,
                originalMute: previous.originalMute,
                lastSetMute: previous.lastSetMute
            )
        }
        if let mute, mute.writable {
            let shouldMute = requested == 0
            try CoreAudioOutputMute.write(shouldMute, deviceID: device.deviceID, address: mute.address)
            if let previous = originalVolumes[uid] {
                originalVolumes[uid] = VolumeRestoreState(
                    original: previous.original,
                    lastSet: previous.lastSet,
                    selector: previous.selector,
                    originalMute: previous.originalMute,
                    lastSetMute: shouldMute
                )
            }
        }
        return Double(actual)
    }

    private func restoreOutputVolumes() {
        for (uid, saved) in originalVolumes {
            guard let device = latestDevices.first(where: { $0.uid == uid }), device.isAlive else { continue }
            restoreVolume(saved, deviceID: device.deviceID)
            restoreMute(saved, deviceID: device.deviceID)
        }
        originalVolumes.removeAll()
    }

    private func restoreVolume(_ saved: VolumeRestoreState, deviceID: AudioDeviceID) {
        guard let original = saved.original, let lastSet = saved.lastSet,
              let current = CoreAudioOutputVolume.read(deviceID: deviceID), current.writable,
              current.address.mSelector == saved.selector,
              abs(current.value - lastSet) <= 0.015 else { return }
        try? CoreAudioOutputVolume.write(original, deviceID: deviceID, address: current.address)
    }

    private func restoreMute(_ saved: VolumeRestoreState, deviceID: AudioDeviceID) {
        guard let originalMute = saved.originalMute, let lastSetMute = saved.lastSetMute,
              let current = CoreAudioOutputMute.read(deviceID: deviceID), current.writable,
              current.value == lastSetMute else { return }
        try? CoreAudioOutputMute.write(originalMute, deviceID: deviceID, address: current.address)
    }

    private func refresh() {
        guard started else { return }
        guard let ids = readDeviceIDs() else { return }
        let present = Set(ids)
        for id in Array(deviceListeners.keys) where !present.contains(id) {
            removeListeners(for: id)
        }

        let snapshots = ids.compactMap { id -> AudioDeviceSnapshot? in
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            // A process tap's private aggregate is an implementation resource, not a user input device.
            guard !uid.hasPrefix(AudioCaptureCoordinator.tapAggregateUIDPrefix) else {
                removeListeners(for: id)
                return nil
            }
            installListeners(for: id)
            guard let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
            let volume = CoreAudioOutputVolume.read(deviceID: id)
            let mute = CoreAudioOutputMute.read(deviceID: id)
            return AudioDeviceSnapshot(
                deviceID: id,
                uid: uid,
                name: name,
                isAlive: boolProperty(id, kAudioDevicePropertyDeviceIsAlive) ?? false,
                inputChannels: channelCount(id, kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(id, kAudioDevicePropertyScopeOutput),
                nominalSampleRate: doubleProperty(id, kAudioDevicePropertyNominalSampleRate) ?? 0,
                outputVolume: volume.map { Double($0.value) },
                canSetOutputVolume: volume?.writable ?? false,
                outputMuted: mute?.value,
                canSetOutputMute: mute?.writable ?? false
            )
        }
        latestDevices = snapshots
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshots) }
    }

    private func readDeviceIDs() -> [AudioDeviceID]? {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard ids.withUnsafeMutableBytes({ bytes in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!)
        }) == noErr else { return nil }
        return ids
    }

    private func installListeners(for id: AudioDeviceID) {
        guard deviceListeners[id] == nil else { return }
        let selectors = [
            Self.address(kAudioObjectPropertyName), Self.address(kAudioDevicePropertyDeviceIsAlive),
            Self.address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput),
            Self.address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput),
            Self.address(kAudioDevicePropertyNominalSampleRate),
            Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput),
            Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput),
            Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        ]
        var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        for var address in selectors {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            if AudioObjectAddPropertyListenerBlock(id, &address, queue, listener) == noErr {
                listeners.append((address, listener))
            }
        }
        deviceListeners[id] = listeners
    }

    private func removeListeners(for id: AudioDeviceID) {
        guard let listeners = deviceListeners.removeValue(forKey: id) else { return }
        for (storedAddress, listener) in listeners {
            var address = storedAddress
            AudioObjectRemovePropertyListenerBlock(id, &address, queue, listener)
        }
    }

    private func removeDeviceListeners() {
        for id in Array(deviceListeners.keys) {
            removeListeners(for: id)
        }
    }

    private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func doubleProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Double? {
        var address = Self.address(selector)
        var value = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func boolProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool? {
        var address = Self.address(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func channelCount(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = Self.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

extension CoreAudioDeviceCatalog {
    func setOutputMuted(uid: String, muted: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async { [weak self] in
            let result: Result<Bool, Error>
            do {
                guard let self else { throw VolumeError.deviceUnavailable }
                result = try .success(setOutputMuted(uid: uid, muted: muted))
                refresh()
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func setOutputMuted(uid: String, muted: Bool) throws -> Bool {
        guard started, let device = latestDevices.first(where: { $0.uid == uid }),
              device.isAlive, device.outputChannels > 0 else { throw VolumeError.deviceUnavailable }
        guard let control = CoreAudioOutputMute.read(deviceID: device.deviceID), control.writable
        else { throw VolumeError.muteUnsupported }

        if originalVolumes[uid] == nil {
            originalVolumes[uid] = VolumeRestoreState(
                original: nil, lastSet: nil, selector: nil,
                originalMute: control.value, lastSetMute: control.value
            )
        }
        try CoreAudioOutputMute.write(muted, deviceID: device.deviceID, address: control.address)
        if let previous = originalVolumes[uid] {
            originalVolumes[uid] = VolumeRestoreState(
                original: previous.original, lastSet: previous.lastSet, selector: previous.selector,
                originalMute: previous.originalMute, lastSetMute: muted
            )
        }
        return CoreAudioOutputMute.read(deviceID: device.deviceID)?.value ?? muted
    }
}

enum VolumeError: LocalizedError {
    case deviceUnavailable
    case unsupported
    case muteUnsupported
    case audioStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "The output device is unavailable."
        case .unsupported: "This output device does not expose a writable main volume control."
        case .muteUnsupported: "This output device does not expose a writable mute control."
        case let .audioStatus(status): "Core Audio could not change the output device control (status \(status))."
        }
    }
}

private enum CoreAudioOutputVolume {
    struct Control {
        let address: AudioObjectPropertyAddress
        let value: Float32
        let writable: Bool
    }

    static func read(deviceID: AudioDeviceID) -> Control? {
        var readable: Control?
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
                  value.isFinite, (0 ... 1).contains(value) else { continue }
            var settable = DarwinBoolean(false)
            let writable = AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
            let control = Control(address: address, value: value, writable: writable)
            if writable {
                return control
            }
            readable = readable ?? control
        }
        return readable
    }

    static func write(_ value: Float32, deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) throws {
        var address = address
        var value = value
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
        guard status == noErr else { throw VolumeError.audioStatus(status) }
    }
}
