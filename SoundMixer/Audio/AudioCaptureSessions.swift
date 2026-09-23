import AudioToolbox
import CoreAudio
import Foundation

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
              (1 ... 2).contains(format.mChannelsPerFrame),
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
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(2 * MemoryLayout<Float>.size),
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat)
    }

    private func installInputCallback(_ unit: AudioUnit) throws {
        var callback = AURenderCallbackStruct(inputProc: { ref, flags, time, bus, frames, _ in
            let session = Unmanaged<AudioInputCaptureSession>.fromOpaque(ref).takeUnretainedValue()
            guard let unit = session.unit, let storage = session.sampleStorage, frames <= 8192 else { return kAudio_ParamError }
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: UInt32(session.channels),
                mDataByteSize: frames * UInt32(session.format.mBytesPerFrame),
                mData: storage
            ))
            let status = AudioUnitRender(unit, flags, time, bus, frames, &list)
            if status == noErr, let owner = session.owner {
                withUnsafePointer(to: &list) { buffers in
                    owner.deliver(id: session.captureID, buffers: buffers, frames: frames, format: session.format)
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
