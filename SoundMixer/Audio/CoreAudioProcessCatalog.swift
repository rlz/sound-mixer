import AppKit
import CoreAudio
import Foundation

struct AudioProcessSnapshot: Equatable, Sendable {
    let processID: pid_t
    let applicationID: String
    let name: String
    let isProducingOutput: Bool
}

/// Discovers output-producing processes. PIDs are transient and are never persisted.
final class CoreAudioProcessCatalog {
    var onChange: (([AudioProcessSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.process-catalog")
    private var timer: DispatchSourceTimer?

    deinit { stop() }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .seconds(2))
            timer.setEventHandler { [weak self] in self?.refresh() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func refresh() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard objects.withUnsafeMutableBytes({ bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }) == noErr else { return }

        let processes = objects.compactMap { snapshot(for: $0) }.filter { !$0.applicationID.isEmpty }
        DispatchQueue.main.async { [weak self] in self?.onChange?(processes) }
    }

    private func snapshot(for object: AudioObjectID) -> AudioProcessSnapshot? {
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid_t(0)
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
              pid != getpid()
        else { return nil }

        var bundleAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundle: Unmanaged<CFString>?
        var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
              let applicationID = bundle?.takeRetainedValue() as String?
        else { return nil }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running)
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? applicationID
        return AudioProcessSnapshot(
            processID: pid,
            applicationID: applicationID,
            name: name,
            isProducingOutput: running != 0
        )
    }
}
