import AudioToolbox
import CoreAudio
import Foundation

enum AudioCaptureState: Equatable {
    case stopped
    case starting
    case capturing
    case permissionDenied
    case unavailable(String)
}

/// Owns source capture resources. Each source is started and reported independently.
/// The callback is invoked on Core Audio's realtime thread; consumers must not allocate,
/// block, log, access files, or call WebKit from it.
final class AudioCaptureCoordinator {
    typealias AudioHandler = (String, UnsafePointer<AudioBufferList>, UInt32, AudioStreamBasicDescription) -> Void

    var onStateChange: ((String, AudioCaptureState) -> Void)?
    var onAudio: AudioHandler?

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.audio-capture")
    private var processSessions: [String: ProcessSession] = [:]
    private var inputSessions: [String: InputSession] = [:]

    func startApplication(id: String, processID: pid_t) {
        queue.async { [weak self] in self?.startProcess(id: id, processID: processID) }
    }

    func startInput(uid: String, deviceID: AudioDeviceID) {
        queue.async { [weak self] in self?.startInputOnQueue(uid: uid, deviceID: deviceID) }
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
        processSessions.removeValue(forKey: id)?.stop()
        publish(id, .starting)
        do {
            guard processID != getpid() else { throw CaptureError.selfCapture }
            var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var pid = processID
            var process = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process
            )
            guard status == noErr, process != kAudioObjectUnknown else { throw CaptureError.processUnavailable }
            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.name = "Sound Mixer source"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            var tap = AudioObjectID(kAudioObjectUnknown)
            let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
            guard tapStatus == noErr else { throw CaptureError.audioStatus(tapStatus) }
            let tapUID: CFString = try Self.read(tap, kAudioTapPropertyUID)
            let aggregateUID = "com.rlz.soundmixer.tap.\(UUID().uuidString)" as CFString
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
            let session = ProcessSession(id: id, tap: tap, aggregate: aggregate, owner: self)
            do {
                try session.start()
                processSessions[id] = session
                publish(id, .capturing)
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
        inputSessions.removeValue(forKey: uid)?.stop()
        publish(uid, .starting)
        do {
            let session = try InputSession(uid: uid, deviceID: deviceID, owner: self)
            try session.start()
            inputSessions[uid] = session
            publish(uid, .capturing)
        } catch {
            publish(uid, .unavailable(error.localizedDescription))
        }
    }

    private func deliver(id: String, buffers: UnsafePointer<AudioBufferList>, frames: UInt32, format: AudioStreamBasicDescription) {
        onAudio?(id, buffers, frames, format)
    }

    private func publish(_ id: String, _ state: AudioCaptureState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(id, state) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> T {
        var propertyAddress = address(selector)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, value)
        guard status == noErr else { throw CaptureError.audioStatus(status) }
        return value.pointee
    }

    fileprivate enum CaptureError: LocalizedError, Equatable {
        case selfCapture
        case processUnavailable
        case permissionDenied
        case unsupportedFormat
        case audioStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .selfCapture: "Sound Mixer cannot capture itself."
            case .processUnavailable: "The application no longer has an audio process."
            case .permissionDenied: "System Audio Recording permission was denied."
            case .unsupportedFormat: "The source format is not supported."
            case let .audioStatus(status): "Core Audio failed with status \(status)."
            }
        }
    }

    private final class ProcessSession {
        let id: String
        let tap: AudioObjectID
        let aggregate: AudioObjectID
        weak var owner: AudioCaptureCoordinator?
        var procID: AudioDeviceIOProcID?
        var format = AudioStreamBasicDescription()

        init(id: String, tap: AudioObjectID, aggregate: AudioObjectID, owner: AudioCaptureCoordinator) {
            self.id = id; self.tap = tap; self.aggregate = aggregate; self.owner = owner
        }

        func start() throws {
            format = try AudioCaptureCoordinator.read(tap, kAudioTapPropertyFormat)
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mChannelsPerFrame > 0
            else {
                throw CaptureError.unsupportedFormat
            }
            let status = AudioDeviceCreateIOProcID(aggregate, { _, _, input, _, _, _, context in
                guard let context else { return kAudio_ParamError }
                let session = Unmanaged<ProcessSession>.fromOpaque(context).takeUnretainedValue()
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                let bytesPerFrame = max(1, Int(session.format.mBytesPerFrame))
                let frames = buffers.first.map { UInt32(Int($0.mDataByteSize) / bytesPerFrame) } ?? 0
                session.owner?.deliver(id: session.id, buffers: input, frames: frames, format: session.format)
                return noErr
            }, Unmanaged.passUnretained(self).toOpaque(), &procID)
            guard status == noErr, let procID else { throw CaptureError.audioStatus(status) }
            let startStatus = AudioDeviceStart(aggregate, procID)
            guard startStatus == noErr else { throw CaptureError.audioStatus(startStatus) }
        }

        func stop() {
            if let procID {
                AudioDeviceStop(aggregate, procID); AudioDeviceDestroyIOProcID(aggregate, procID); self.procID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
            AudioHardwareDestroyProcessTap(tap)
        }
    }

    private final class InputSession {
        let uid: String
        let deviceID: AudioDeviceID
        weak var owner: AudioCaptureCoordinator?
        var unit: AudioUnit?
        var sampleStorage: UnsafeMutablePointer<Float>?
        var channels = 1
        var format = AudioStreamBasicDescription()

        init(uid: String, deviceID: AudioDeviceID, owner: AudioCaptureCoordinator) throws {
            self.uid = uid; self.deviceID = deviceID; self.owner = owner
            var description = AudioComponentDescription(
                componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard let component = AudioComponentFindNext(nil, &description) else { throw CaptureError.audioStatus(kAudio_ParamError) }
            var created: AudioUnit?
            var status = AudioComponentInstanceNew(component, &created)
            guard status == noErr, let created else { throw CaptureError.audioStatus(status) }
            unit = created
            var enable: UInt32 = 1
            var disable: UInt32 = 0
            status = AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, 4)
            guard status == noErr else { throw CaptureError.audioStatus(status) }
            status = AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, 4)
            guard status == noErr else { throw CaptureError.audioStatus(status) }
            var selectedDevice = deviceID
            status = AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selectedDevice, 4)
            guard status == noErr else { throw CaptureError.audioStatus(status) }
        }

        func start() throws {
            guard let unit else { throw CaptureError.audioStatus(kAudio_ParamError) }
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let formatStatus = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, &formatSize)
            guard formatStatus == noErr, format.mChannelsPerFrame > 0, format.mBytesPerFrame > 0 else {
                throw CaptureError.audioStatus(formatStatus)
            }
            channels = Int(format.mChannelsPerFrame)
            sampleStorage = .allocate(capacity: 8192 * channels)
            var callback = AURenderCallbackStruct(inputProc: { ref, flags, time, bus, frames, _ in
                let session = Unmanaged<InputSession>.fromOpaque(ref).takeUnretainedValue()
                guard let unit = session.unit, let storage = session.sampleStorage, frames <= 8192 else { return kAudio_ParamError }
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(session.channels),
                    mDataByteSize: frames * UInt32(session.format.mBytesPerFrame),
                    mData: storage
                ))
                let status = AudioUnitRender(unit, flags, time, bus, frames, &list)
                if status == noErr, let owner = session.owner {
                    withUnsafePointer(to: &list) { buffers in
                        owner.deliver(id: session.uid, buffers: buffers, frames: frames, format: session.format)
                    }
                }
                return status
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            let callbackStatus = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
            guard callbackStatus == noErr else { throw CaptureError.audioStatus(callbackStatus) }
            let initializeStatus = AudioUnitInitialize(unit)
            guard initializeStatus == noErr else { throw CaptureError.audioStatus(initializeStatus) }
            let startStatus = AudioOutputUnitStart(unit)
            guard startStatus == noErr else { throw CaptureError.audioStatus(startStatus) }
        }

        func stop() {
            if let unit {
                AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit); self.unit = nil
            }
            sampleStorage?.deallocate()
            sampleStorage = nil
        }
    }
}
