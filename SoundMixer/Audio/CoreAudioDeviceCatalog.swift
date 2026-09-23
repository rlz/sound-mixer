import CoreAudio
import Foundation

struct AudioDeviceSnapshot: Equatable, Sendable {
    let uid: String
    let name: String
    let isAlive: Bool
    let inputChannels: Int
    let outputChannels: Int
    let nominalSampleRate: Double
}

final class CoreAudioDeviceCatalog {
    var onChange: (([AudioDeviceSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.core-audio-catalog")
    private var deviceListeners: [AudioDeviceID: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?
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
            var address = Self.address(kAudioHardwarePropertyDevices)
            if let deviceListListener {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, deviceListListener)
                self.deviceListListener = nil
            }
            removeDeviceListeners()
        }
    }

    private func refresh() {
        guard let ids = readDeviceIDs() else { return }
        let present = Set(ids)
        for id in Array(deviceListeners.keys) where !present.contains(id) {
            removeListeners(for: id)
        }

        let snapshots = ids.compactMap { id -> AudioDeviceSnapshot? in
            installListeners(for: id)
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName)
            else { return nil }
            return AudioDeviceSnapshot(
                uid: uid,
                name: name,
                isAlive: boolProperty(id, kAudioDevicePropertyDeviceIsAlive) ?? false,
                inputChannels: channelCount(id, kAudioDevicePropertyScopeInput),
                outputChannels: channelCount(id, kAudioDevicePropertyScopeOutput),
                nominalSampleRate: doubleProperty(id, kAudioDevicePropertyNominalSampleRate) ?? 0
            )
        }
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
            Self.address(kAudioDevicePropertyNominalSampleRate)
        ]
        var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        for var address in selectors {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            AudioObjectAddPropertyListenerBlock(id, &address, queue, listener)
            listeners.append((address, listener))
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
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String?
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
