import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

final class AudioProcessCaptureSession {
    let captureID: String
    let tap: AudioObjectID
    let aggregate: AudioObjectID
    weak var owner: AudioCaptureCoordinator?
    var procID: AudioDeviceIOProcID?
    var format = AudioStreamBasicDescription()

    init(id: String, tap: AudioObjectID, aggregate: AudioObjectID, owner: AudioCaptureCoordinator) {
        captureID = "application:\(id)"
        self.tap = tap
        self.aggregate = aggregate
        self.owner = owner
    }

    func start() throws {
        format = try AudioCaptureCoordinator.read(tap, kAudioTapPropertyFormat)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame > 0
        else {
            throw AudioCaptureCoordinator.CaptureError.unsupportedFormat
        }

        let status = AudioDeviceCreateIOProcID(aggregate, { _, _, input, _, _, _, context in
            guard let context else { return kAudio_ParamError }
            let session = Unmanaged<AudioProcessCaptureSession>.fromOpaque(context).takeUnretainedValue()
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let bytesPerFrame = max(1, Int(session.format.mBytesPerFrame))
            let frames = buffers.first.map { UInt32(Int($0.mDataByteSize) / bytesPerFrame) } ?? 0
            session.owner?.deliver(id: session.captureID, buffers: input, frames: frames, format: session.format)
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque(), &procID)
        guard status == noErr, let procID else { throw AudioCaptureCoordinator.CaptureError.audioStatus(status) }
        let startStatus = AudioDeviceStart(aggregate, procID)
        guard startStatus == noErr else { throw AudioCaptureCoordinator.CaptureError.audioStatus(startStatus) }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregate, procID)
            AudioDeviceDestroyIOProcID(aggregate, procID)
            self.procID = nil
        }
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tap)
    }
}

final class AudioInputCaptureSession {
    let captureID: String
    let deviceID: AudioDeviceID
    weak var owner: AudioCaptureCoordinator?
    var unit: AudioUnit?
    var sampleStorage: UnsafeMutablePointer<Float>?
    var channels = 1
    var format = AudioStreamBasicDescription()
    private let renderStatus = Atomic<Int32>(noErr)
    private let lastRenderedAt = Atomic<UInt64>(0)
    private var startedAt: UInt64 = 0

    var captureState: AudioCaptureState {
        let status = renderStatus.load(ordering: .relaxed)
        if status != noErr {
            return .unavailable("Microphone capture failed with Core Audio status \(status).")
        }
        let renderedAt = lastRenderedAt.load(ordering: .acquiring)
        let now = DispatchTime.now().uptimeNanoseconds
        if renderedAt > 0, now &- renderedAt <= 500_000_000 {
            return .capturing
        }
        if startedAt > 0, now &- startedAt > 1_000_000_000 {
            return .unavailable("The microphone is not delivering audio. Check microphone access in System Settings.")
        }
        return .starting
    }

    init(uid: String, deviceID: AudioDeviceID, owner: AudioCaptureCoordinator) throws {
        captureID = "input:\(uid)"
        self.deviceID = deviceID
        self.owner = owner
        do {
            try createUnit()
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    func start() throws {
        guard let unit else { throw AudioCaptureCoordinator.CaptureError.audioStatus(kAudio_ParamError) }
        try configureClientFormat(unit)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, &formatSize)
        guard formatStatus == noErr,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              (1 ... 64).contains(format.mChannelsPerFrame),
              format.mBytesPerFrame >= UInt32(MemoryLayout<Float>.size),
              format.mSampleRate.isFinite, format.mSampleRate > 0
        else {
            throw AudioCaptureCoordinator.CaptureError.audioStatus(formatStatus)
        }
        channels = Int(format.mChannelsPerFrame)
        sampleStorage = .allocate(capacity: 8192 * channels)
        try installInputCallback(unit)
        let initializeStatus = AudioUnitInitialize(unit)
        guard initializeStatus == noErr else { throw AudioCaptureCoordinator.CaptureError.audioStatus(initializeStatus) }
        let startStatus = AudioOutputUnitStart(unit)
        guard startStatus == noErr else { throw AudioCaptureCoordinator.CaptureError.audioStatus(startStatus) }
        startedAt = DispatchTime.now().uptimeNanoseconds
    }

    func stop() {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            self.unit = nil
        }
        sampleStorage?.deallocate()
        sampleStorage = nil
    }

    private func createUnit() throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioCaptureCoordinator.CaptureError.audioStatus(kAudio_ParamError)
        }
        var created: AudioUnit?
        let status = AudioComponentInstanceNew(component, &created)
        guard status == noErr, let created else { throw AudioCaptureCoordinator.CaptureError.audioStatus(status) }
        unit = created
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        try set(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable)
        try set(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable)
        var selectedDevice = deviceID
        try set(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selectedDevice)
    }

    private func configureClientFormat(_ unit: AudioUnit) throws {
        var hardwareFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardwareFormat, &size
        )
        guard status == noErr else { throw AudioCaptureCoordinator.CaptureError.audioStatus(status) }
        guard hardwareFormat.mSampleRate.isFinite, hardwareFormat.mSampleRate > 0,
              (1 ... 64).contains(hardwareFormat.mChannelsPerFrame)
        else {
            throw AudioCaptureCoordinator.CaptureError.unsupportedInputFormat(
                channels: Int(hardwareFormat.mChannelsPerFrame),
                sampleRate: hardwareFormat.mSampleRate
            )
        }
        // AUHAL input must use the device rate and full channel layout. The
        // source fanout resamples to 48 kHz after capture.
        let bytesPerFrame = hardwareFormat.mChannelsPerFrame * UInt32(MemoryLayout<Float>.size)
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: hardwareFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: hardwareFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat)
    }

    private func installInputCallback(_ unit: AudioUnit) throws {
        var callback = AURenderCallbackStruct(inputProc: { ref, flags, time, _, frames, _ in
            let session = Unmanaged<AudioInputCaptureSession>.fromOpaque(ref).takeUnretainedValue()
            guard let unit = session.unit, let storage = session.sampleStorage, frames <= 8192 else {
                session.renderStatus.store(kAudio_ParamError, ordering: .relaxed)
                return kAudio_ParamError
            }
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: UInt32(session.channels),
                mDataByteSize: frames * UInt32(session.format.mBytesPerFrame),
                mData: storage
            ))
            let status = AudioUnitRender(unit, flags, time, 1, frames, &list)
            session.renderStatus.store(status, ordering: .relaxed)
            if status == noErr, let owner = session.owner {
                withUnsafePointer(to: &list) { buffers in
                    owner.deliver(id: session.captureID, buffers: buffers, frames: frames, format: session.format)
                }
                if frames > 0 {
                    session.lastRenderedAt.store(DispatchTime.now().uptimeNanoseconds, ordering: .releasing)
                }
            }
            return status
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try set(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback)
    }

    private func set(
        _ unit: AudioUnit,
        _ property: AudioUnitPropertyID,
        _ scope: AudioUnitScope,
        _ element: AudioUnitElement,
        _ value: inout some Any
    ) throws {
        let status = withUnsafeBytes(of: &value) { bytes in
            AudioUnitSetProperty(unit, property, scope, element, bytes.baseAddress, UInt32(bytes.count))
        }
        guard status == noErr else { throw AudioCaptureCoordinator.CaptureError.audioStatus(status) }
    }
}
