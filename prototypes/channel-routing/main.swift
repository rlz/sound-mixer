import AudioToolbox
import CoreAudio
import Foundation

struct Device {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputs: Int
    let outputs: Int
    let rate: Double
}

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
        throw NSError(domain: "ChannelRouting", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(action): OSStatus \(status)"])
    }
}

func property<T>(
    _ id: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope,
    as _: T.Type
) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
    defer { storage.deallocate() }
    try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage), "read property \(selector)")
    return storage.load(as: T.self)
}

func channelCount(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) throws -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size), "stream configuration size")
    let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage), "stream configuration")
    let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func devices() throws -> [Device] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size), "device list size")
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    try ids.withUnsafeMutableBytes { bytes in
        try check(AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!), "device list")
    }
    return try ids.map { id in
        let uid: CFString = try property(id, kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal, as: CFString.self)
        let name: CFString = try property(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, as: CFString.self)
        let rate: Float64 = try property(id, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, as: Float64.self)
        return try Device(
            id: id,
            uid: uid as String,
            name: name as String,
            inputs: channelCount(id, kAudioDevicePropertyScopeInput),
            outputs: channelCount(id, kAudioDevicePropertyScopeOutput),
            rate: rate
        )
    }
}

func setProperty(
    _ unit: AudioUnit,
    _ selector: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ bus: AudioUnitElement,
    _ value: inout some Any
) throws {
    let status = withUnsafeBytes(of: &value) { bytes in
        AudioUnitSetProperty(unit, selector, scope, bus, bytes.baseAddress, UInt32(bytes.count))
    }
    try check(status, "set AudioUnit property \(selector)")
}

func makeUnit(_ device: Device, input: Bool) throws -> AudioUnit {
    var description = AudioComponentDescription(
        componentType: kAudioUnitType_Output,
        componentSubType: kAudioUnitSubType_HALOutput,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &description) else {
        throw NSError(domain: "ChannelRouting", code: -1, userInfo: [NSLocalizedDescriptionKey: "HAL Output component unavailable"])
    }
    var result: AudioUnit?
    try check(AudioComponentInstanceNew(component, &result), "create HAL unit")
    guard let unit = result else { throw NSError(domain: "ChannelRouting", code: -2) }
    do {
        var enable: UInt32 = input ? 1 : 0
        var disable: UInt32 = input ? 0 : 1
        var id = device.id
        try setProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable)
        try setProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable)
        try setProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id)
        return unit
    } catch {
        AudioComponentInstanceDispose(unit)
        throw error
    }
}

func format(rate: Double, channels: Int) -> AudioStreamBasicDescription {
    let count = UInt32(channels)
    return AudioStreamBasicDescription(
        mSampleRate: rate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: count * 4,
        mFramesPerPacket: 1,
        mBytesPerFrame: count * 4,
        mChannelsPerFrame: count,
        mBitsPerChannel: 32,
        mReserved: 0
    )
}

final class OutputState {
    let channels: Int
    let selected: [Int]
    let step: Double
    var phase = 0.0
    var frames: UInt64 = 0

    init(channels: Int, selected: [Int], rate: Double) {
        self.channels = channels
        self.selected = selected
        step = 2 * Double.pi * 440 / rate
    }
}

let outputCallback: AURenderCallback = { ref, _, _, _, frames, data in
    guard let data else { return kAudio_ParamError }
    let state = Unmanaged<OutputState>.fromOpaque(ref).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(data)
    // The requested interleaved client format must produce one buffer.
    for buffer in buffers {
        guard let pointer = buffer.mData else { return kAudio_ParamError }
        memset(pointer, 0, Int(buffer.mDataByteSize))
    }
    guard buffers.count == 1, buffers[0].mNumberChannels == state.channels,
          let pointer = buffers[0].mData else { return kAudio_ParamError }
    let samples = pointer.assumingMemoryBound(to: Float.self)
    for frame in 0 ..< Int(frames) {
        let value = Float(sin(state.phase) * 0.02)
        state.phase += state.step
        if state.phase >= 2 * Double.pi {
            state.phase -= 2 * Double.pi
        }
        for channel in state.selected {
            samples[frame * state.channels + channel] = value
        }
    }
    state.frames += UInt64(frames)
    return noErr
}

final class InputState {
    let unit: AudioUnit
    let channels: Int
    let capacity = 8192
    let samples: UnsafeMutablePointer<Float>
    let peaks: UnsafeMutablePointer<Float>
    var frames: UInt64 = 0

    init(unit: AudioUnit, channels: Int) {
        self.unit = unit
        self.channels = channels
        samples = .allocate(capacity: capacity * channels)
        peaks = .allocate(capacity: channels)
        peaks.initialize(repeating: 0, count: channels)
    }

    deinit {
        samples.deallocate()
        peaks.deinitialize(count: channels)
        peaks.deallocate()
    }
}

let inputCallback: AURenderCallback = { ref, flags, time, _, frames, _ in
    let state = Unmanaged<InputState>.fromOpaque(ref).takeUnretainedValue()
    guard Int(frames) <= state.capacity else { return kAudio_ParamError }
    let buffer = AudioBuffer(
        mNumberChannels: UInt32(state.channels),
        mDataByteSize: frames * UInt32(state.channels * MemoryLayout<Float>.size),
        mData: state.samples
    )
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
    let status = AudioUnitRender(state.unit, flags, time, 1, frames, &list)
    guard status == noErr else { return status }
    for frame in 0 ..< Int(frames) {
        for channel in 0 ..< state.channels {
            let index = frame * state.channels + channel
            state.peaks[channel] = max(state.peaks[channel], abs(state.samples[index]))
        }
    }
    state.frames += UInt64(frames)
    return noErr
}

func startInput(_ device: Device) throws -> (AudioUnit, InputState) {
    let unit = try makeUnit(device, input: true)
    do {
        let state = InputState(unit: unit, channels: device.inputs)
        var inputFormat = format(rate: device.rate, channels: device.inputs)
        var inputProc = AURenderCallbackStruct(inputProc: inputCallback, inputProcRefCon: Unmanaged.passUnretained(state).toOpaque())
        try setProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inputFormat)
        try setProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputProc)
        try check(AudioUnitInitialize(unit), "initialize input")
        try check(AudioOutputUnitStart(unit), "start input")
        return (unit, state)
    } catch {
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        throw error
    }
}

func verifyLoopback(_ reader: InputState, selected: [Int]) throws {
    let peaks = (0 ..< reader.channels).map { reader.peaks[$0] }
    print("Loopback frames: \(reader.frames); channel peaks: \(peaks)")
    let selectedAudible = selected.allSatisfy { peaks[$0] > 0.005 }
    let unselectedSilent = peaks.enumerated().allSatisfy { selected.contains($0.offset) || $0.element < 0.001 }
    guard selectedAudible, unselectedSilent else {
        throw NSError(
            domain: "ChannelRouting",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Loopback does not match selected channels"]
        )
    }
    print("PASS: selected channels have signal; unselected channels are silent")
}

func run(_ device: Device, selected: [Int], seconds: Int) throws {
    let output = try makeUnit(device, input: false)
    defer { AudioOutputUnitStop(output); AudioUnitUninitialize(output); AudioComponentInstanceDispose(output) }
    let writer = OutputState(channels: device.outputs, selected: selected, rate: device.rate)
    var outputFormat = format(rate: device.rate, channels: device.outputs)
    var outputProc = AURenderCallbackStruct(inputProc: outputCallback, inputProcRefCon: Unmanaged.passUnretained(writer).toOpaque())
    try setProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputFormat)
    try setProperty(output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outputProc)

    var input: AudioUnit?
    var reader: InputState?
    defer {
        if let input {
            AudioOutputUnitStop(input)
            AudioUnitUninitialize(input)
            AudioComponentInstanceDispose(input)
        }
    }
    if device.inputs == device.outputs {
        (input, reader) = try startInput(device)
    }
    try check(AudioUnitInitialize(output), "initialize output")
    try check(AudioOutputUnitStart(output), "start output")
    print("Writing 440 Hz at amplitude 0.02 to \(device.uid), channels \(selected.map { $0 + 1 }); \(seconds) s")
    Thread.sleep(forTimeInterval: Double(seconds))
    try check(AudioOutputUnitStop(output), "stop output")
    if let input {
        try check(AudioOutputUnitStop(input), "stop input")
    }
    print("Output frames: \(writer.frames)")
    if let reader {
        try verifyLoopback(reader, selected: selected)
    } else {
        print("No matching input channels; output callback verified, physical signal not measured")
    }
}

do {
    let all = try devices()
    if CommandLine.arguments.count == 1 || CommandLine.arguments[1] == "list" {
        for device in all {
            print("\(device.uid) | \(device.name) | input=\(device.inputs) output=\(device.outputs) rate=\(device.rate)")
        }
    } else if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "probe" {
        guard let device = all.first(where: { $0.uid == CommandLine.arguments[2] }),
              let seconds = Int(CommandLine.arguments[4]), (1 ... 30).contains(seconds)
        else {
            throw NSError(
                domain: "ChannelRouting",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Usage: channel-routing list | probe UID CHANNEL[,CHANNEL] SECONDS"]
            )
        }
        let parts = CommandLine.arguments[3].split(separator: ",", omittingEmptySubsequences: false)
        let channels = parts.compactMap { Int($0) }
        guard (1 ... 2).contains(parts.count), channels.count == parts.count, Set(channels).count == channels.count,
              channels.allSatisfy({ (1 ... device.outputs).contains($0) })
        else {
            throw NSError(
                domain: "ChannelRouting",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Choose one channel or two distinct channels in 1...\(device.outputs)"]
            )
        }
        try run(device, selected: channels.map { $0 - 1 }, seconds: seconds)
    } else {
        throw NSError(
            domain: "ChannelRouting",
            code: -5,
            userInfo: [NSLocalizedDescriptionKey: "Usage: channel-routing list | probe UID CHANNEL[,CHANNEL] SECONDS"]
        )
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
