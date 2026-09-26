import AudioToolbox
import CoreAudio
import Foundation

enum AudioCaptureState: Equatable {
    case stopped
    case starting
    case capturing
    case idle
    case permissionDenied
    case unavailable(String)
}

/// Owns source capture resources. Each source is started and reported independently.
/// The callback is invoked on Core Audio's realtime thread; consumers must not allocate,
/// block, log, access files, or call WebKit from it.
final class AudioCaptureCoordinator {
    typealias AudioHandler = (String, UnsafePointer<AudioBufferList>, UInt32, AudioStreamBasicDescription) -> Void
    static let tapAggregateUIDPrefix = "com.rlz.soundmixer.tap."

    var onStateChange: ((String, AudioCaptureState) -> Void)?
    var onAudio: AudioHandler?

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.audio-capture")
    private var processSessions: [String: AudioProcessCaptureSession] = [:]
    private var inputSessions: [String: AudioInputCaptureSession] = [:]
    private var stateTimer: DispatchSourceTimer?
    private var publishedStates: [String: AudioCaptureState] = [:]

    init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for (id, session) in processSessions {
                publish(id, session.captureState)
            }
            for (uid, session) in inputSessions {
                publish(uid, session.captureState)
            }
        }
        timer.resume()
        stateTimer = timer
    }

    deinit { stateTimer?.cancel() }

    func startApplication(id: String, processID: pid_t) {
        queue.async { [weak self] in self?.startProcess(id: id, processID: processID) }
    }

    func startOutputMeter(uid: String, meter: RealtimePeakMeter) {
        queue.async { [weak self] in
            guard let self else { return }
            let description = CATapDescription(excludingProcesses: [], deviceUID: uid, stream: 0)
            description.name = "Sound Mixer output meter"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            startTap(id: "device:\(uid)", description: description, meter: meter)
        }
    }

    func startInput(uid: String, deviceID: AudioDeviceID) {
        queue.async { [weak self] in self?.startInputOnQueue(uid: uid, deviceID: deviceID) }
    }

    func reportUnavailable(id: String, reason: String) {
        queue.async { [weak self] in self?.publish(id, .unavailable(reason)) }
    }

    func stop(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if let session = processSessions.removeValue(forKey: id) {
                session.stop()
            }
            if let session = inputSessions.removeValue(forKey: id) {
                session.stop()
            }
            publish(id, .stopped)
        }
    }

    func stopAll() {
        queue.sync {
            for (id, session) in processSessions {
                session.stop(); publish(id, .stopped)
            }
            for (id, session) in inputSessions {
                session.stop(); publish(id, .stopped)
            }
            processSessions.removeAll()
            inputSessions.removeAll()
        }
    }

    private func startProcess(id: String, processID: pid_t) {
        let key = "application:\(id)"
        if processSessions[key]?.processID == processID {
            return
        }
        processSessions.removeValue(forKey: key)?.stop()
        publish(key, .starting)
        do {
            try validateCaptureProcess(processID)
            let process = try processObjectID(for: processID)
            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.name = "Sound Mixer source"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            startTap(id: key, description: description, processID: processID)
        } catch {
            publish(key, .unavailable(error.localizedDescription))
        }
    }

    private func startTap(
        id: String,
        description: CATapDescription,
        meter: RealtimePeakMeter? = nil,
        processID: pid_t? = nil
    ) {
        processSessions.removeValue(forKey: id)?.stop()
        publish(id, .starting)
        do {
            var tap = AudioObjectID(kAudioObjectUnknown)
            let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
            guard tapStatus == noErr else { throw CaptureError.audioStatus(tapStatus) }
            let tapUID: CFString
            do {
                tapUID = try Self.read(tap, kAudioTapPropertyUID)
            } catch {
                AudioHardwareDestroyProcessTap(tap)
                throw error
            }
            let aggregateUID = "\(Self.tapAggregateUIDPrefix)\(UUID().uuidString)" as CFString
            let aggregateDescription: CFDictionary = [
                kAudioAggregateDeviceNameKey: "Sound Mixer source",
                kAudioAggregateDeviceUIDKey: aggregateUID as String,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID as String]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ] as CFDictionary
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription, &aggregate)
            guard aggregateStatus == noErr else {
                AudioHardwareDestroyProcessTap(tap)
                throw CaptureError.audioStatus(aggregateStatus)
            }
            let session = AudioProcessCaptureSession(
                id: id, tap: tap, aggregate: aggregate, owner: self, meter: meter, processID: processID
            )
            do {
                try session.start()
                processSessions[id] = session
                publish(id, session.captureState)
            } catch {
                session.stop()
                throw error
            }
        } catch {
            if let captureError = error as? CaptureError, captureError == .permissionDenied {
                publish(id, .permissionDenied)
            } else {
                publish(id, .unavailable(error.localizedDescription))
            }
        }
    }

    private func startInputOnQueue(uid: String, deviceID: AudioDeviceID) {
        if let session = inputSessions[uid], session.matches(deviceID: deviceID) {
            return
        }
        inputSessions.removeValue(forKey: uid)?.stop()
        publish(uid, .starting)
        do {
            let session = try AudioInputCaptureSession(uid: uid, deviceID: deviceID, owner: self)
            try session.start()
            inputSessions[uid] = session
        } catch {
            publish(uid, .unavailable(error.localizedDescription))
        }
    }

    private func validateCaptureProcess(_ processID: pid_t) throws {
        guard processID != getpid() else { throw CaptureError.selfCapture }
    }

    private func processObjectID(for processID: pid_t) throws -> AudioObjectID {
        var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = processID
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process
        )
        guard status == noErr, process != kAudioObjectUnknown else { throw CaptureError.processUnavailable }
        return process
    }

    func deliver(id: String, buffers: UnsafePointer<AudioBufferList>, frames: UInt32, format: AudioStreamBasicDescription) {
        onAudio?(id, buffers, frames, format)
    }

    private func publish(_ id: String, _ state: AudioCaptureState) {
        guard publishedStates[id] != state else { return }
        publishedStates[id] = state
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(id, state) }
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> T {
        var propertyAddress = address(selector)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, value)
        guard status == noErr else { throw CaptureError.audioStatus(status) }
        return value.pointee
    }

    enum CaptureError: LocalizedError, Equatable {
        case selfCapture
        case processUnavailable
        case permissionDenied
        case unsupportedFormat
        case unsupportedInputFormat(channels: Int, sampleRate: Double)
        case audioStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .selfCapture: "Sound Mixer cannot capture itself."
            case .processUnavailable: "The application no longer has an audio process."
            case .permissionDenied: "System Audio Recording permission was denied."
            case .unsupportedFormat: "The source format is not supported."
            case let .unsupportedInputFormat(channels, sampleRate):
                "This input reports \(channels) channels at \(sampleRate) Hz; "
                    + "supported input formats have 1–64 channels and a valid sample rate."
            case let .audioStatus(status): "Core Audio failed with status \(status)."
            }
        }
    }
}
