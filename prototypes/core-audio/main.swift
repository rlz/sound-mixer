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
    guard status == noErr else { throw NSError(
        domain: "CoreAudioProbe",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "\(action): OSStatus \(status)"]
    ) }
}

func setUnitProperty(
    _ unit: AudioUnit,
    _ key: AudioUnitPropertyID,
    _ scope: AudioUnitScope,
    _ bus: AudioUnitElement,
    _ value: inout some Any
) throws {
    let status = withUnsafeBytes(of: &value) { bytes in
        AudioUnitSetProperty(unit, key, scope, bus, bytes.baseAddress, UInt32(bytes.count))
    }
    try check(status, "set AudioUnit property \(key)")
}

func property<T>(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, as _: T.Type) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    let value = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
    defer { value.deallocate() }
    try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, value), "read property \(selector)")
    return value.load(as: T.self)
}

func textProperty(object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
    let value: CFString = try property(object: object, selector: selector, scope: kAudioObjectPropertyScopeGlobal, as: CFString.self)
    return value as String
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
    let list = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func devices() throws -> [Device] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "device list size")
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    try ids.withUnsafeMutableBytes { bytes in
        try check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!),
            "device list"
        )
    }
    return try ids.map { id in
        try Device(
            id: id,
            uid: textProperty(object: id, selector: kAudioDevicePropertyDeviceUID),
            name: textProperty(object: id, selector: kAudioObjectPropertyName),
            inputs: channelCount(id, kAudioDevicePropertyScopeInput),
            outputs: channelCount(id, kAudioDevicePropertyScopeOutput),
            rate: property(
                object: id,
                selector: kAudioDevicePropertyNominalSampleRate,
                scope: kAudioObjectPropertyScopeGlobal,
                as: Float64.self
            )
        )
    }
}

func makeUnit(_ id: AudioDeviceID, input: Bool) throws -> AudioUnit {
    var description = AudioComponentDescription(
        componentType: kAudioUnitType_Output,
        componentSubType: kAudioUnitSubType_HALOutput,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &description) else { throw NSError(domain: "CoreAudioProbe", code: -1) }
    var unit: AudioUnit?
    try check(AudioComponentInstanceNew(component, &unit), "create HAL unit")
    guard let unit else { throw NSError(domain: "CoreAudioProbe", code: -2) }
    do {
        var enable: UInt32 = input ? 1 : 0
        var disable: UInt32 = input ? 0 : 1
        try setUnitProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable)
        try setUnitProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable)
        var device = id
        try setUnitProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device)
        return unit
    } catch {
        AudioComponentInstanceDispose(unit)
        throw error
    }
}

final class Tone {
    var phase = 0.0
    var step: Double
    var framesRendered: UInt64 = 0
    init(rate: Double) {
        step = 2 * Double.pi * 440 / rate
    }
}

let toneCallback: AURenderCallback = { ref, _, _, _, frames, data in
    guard let data else { return kAudio_ParamError }
    let tone = Unmanaged<Tone>.fromOpaque(ref).takeUnretainedValue()
    let list = UnsafeMutableAudioBufferListPointer(data)
    for frame in 0 ..< Int(frames) {
        let sample = Float(sin(tone.phase) * 0.05)
        tone.phase += tone.step
        if tone.phase >= 2 * Double.pi {
            tone.phase -= 2 * Double.pi
        }
        for buffer in list {
            guard let pointer = buffer.mData else { continue }
            let samples = pointer.assumingMemoryBound(to: Float.self)
            let channels = Int(buffer.mNumberChannels)
            for channel in 0 ..< channels {
                samples[frame * channels + channel] = sample
            }
        }
    }
    tone.framesRendered += UInt64(frames)
    return noErr
}

final class Meter {
    let unit: AudioUnit
    let samples: UnsafeMutablePointer<Float>
    var framesRead: UInt64 = 0
    var peak: Float = 0
    init(unit: AudioUnit) {
        self.unit = unit
        samples = .allocate(capacity: 8192)
    }

    deinit { samples.deallocate() }
}

let inputCallback: AURenderCallback = { ref, flags, time, _, frames, _ in
    let meter = Unmanaged<Meter>.fromOpaque(ref).takeUnretainedValue()
    guard frames <= 8192 else { return kAudio_ParamError }
    let buffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * UInt32(MemoryLayout<Float>.size), mData: meter.samples)
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
    let status = AudioUnitRender(meter.unit, flags, time, 1, frames, &list)
    guard status == noErr else { return status }
    for index in 0 ..< Int(frames) {
        meter.peak = max(meter.peak, abs(meter.samples[index]))
    }
    meter.framesRead += UInt64(frames)
    return noErr
}

func streamFormat(rate: Double, channels: UInt32) -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
        mSampleRate: rate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: channels * 4,
        mFramesPerPacket: 1,
        mBytesPerFrame: channels * 4,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 32,
        mReserved: 0
    )
}

func setOutputFormat(_ unit: AudioUnit, rate: Double) throws {
    var format = streamFormat(rate: rate, channels: 2)
    try check(
        AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ),
        "output client format"
    )
}

func outputFormat(_ unit: AudioUnit) throws -> AudioStreamBasicDescription {
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try check(
        AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, &size),
        "read output client format"
    )
    return format
}

struct ProbeOptions {
    let input: Device
    let outputs: [Device]
    let seconds: Int
    let switchRate: Double?
}

func optionValue(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func parseOptions(_ args: [String], devices all: [Device]) throws -> ProbeOptions {
    let inputUID = optionValue("--input", in: args)
    let firstUID = optionValue("--outputs", in: args)
    let secondUID: String? = firstUID.flatMap { _ in
        guard let index = args.firstIndex(of: "--outputs"), index + 2 < args.count else { return nil }
        return args[index + 2]
    }
    guard let input = all.first(where: { $0.uid == inputUID && $0.inputs > 0 }),
          let first = all.first(where: { $0.uid == firstUID && $0.outputs >= 2 }),
          let second = all.first(where: { $0.uid == secondUID && $0.outputs >= 2 }),
          first.id != second.id
    else {
        let usage = "Usage: probe --input UID --outputs STEREO_UID1 STEREO_UID2 " +
            "[--seconds 10] [--switch-client-rate 44100]"
        throw NSError(domain: "CoreAudioProbe", code: -3, userInfo: [NSLocalizedDescriptionKey: usage])
    }
    let seconds = Int(optionValue("--seconds", in: args) ?? "10") ?? 0
    guard (1 ... 120).contains(seconds) else { throw NSError(domain: "CoreAudioProbe", code: -4) }
    let rateText = optionValue("--switch-client-rate", in: args)
    let switchRate = rateText.flatMap(Double.init)
    if rateText != nil, !(switchRate.map { (8000 ... 192_000).contains($0) } ?? false) {
        throw NSError(domain: "CoreAudioProbe", code: -5, userInfo: [NSLocalizedDescriptionKey: "Client rate must be 8000...192000 Hz"])
    }
    return ProbeOptions(input: input, outputs: [first, second], seconds: seconds, switchRate: switchRate)
}

func configureInput(_ unit: AudioUnit, meter: Meter, rate: Double) throws {
    var format = streamFormat(rate: rate, channels: 1)
    try setUnitProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format)
    var callback = AURenderCallbackStruct(inputProc: inputCallback, inputProcRefCon: Unmanaged.passUnretained(meter).toOpaque())
    try setUnitProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback)
}

func configureOutput(_ unit: AudioUnit, tone: Tone, rate: Double) throws {
    try setOutputFormat(unit, rate: rate)
    var callback = AURenderCallbackStruct(inputProc: toneCallback, inputProcRefCon: Unmanaged.passUnretained(tone).toOpaque())
    try setUnitProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback)
}

func switchOutputs(_ units: [AudioUnit], tones: [Tone], devices: [Device], rate: Double) throws {
    for (index, unit) in units.enumerated() {
        try check(AudioOutputUnitStop(unit), "stop output for format change")
        try check(AudioUnitUninitialize(unit), "uninitialize output for format change")
        try setOutputFormat(unit, rate: rate)
        let negotiated = try outputFormat(unit)
        tones[index].step = 2 * Double.pi * 440 / negotiated.mSampleRate
        try check(AudioUnitInitialize(unit), "reinitialize output after format change")
        try check(AudioOutputUnitStart(unit), "restart output after format change")
        let message = "Client format switched: \(devices[index].uid) -> \(negotiated.mSampleRate) Hz, " +
            "hardware nominal \(devices[index].rate) Hz"
        print(message)
    }
}

func observe(_ options: ProbeOptions, units: [AudioUnit], tones: [Tone]) throws {
    for elapsed in 0 ..< options.seconds {
        Thread.sleep(forTimeInterval: 1)
        if let rate = options.switchRate, elapsed == options.seconds / 2 {
            try switchOutputs(units, tones: tones, devices: options.outputs, rate: rate)
        }
        let current = try devices()
        for previous in [options.input] + options.outputs {
            if let updated = current.first(where: { $0.uid == previous.uid }), updated.rate != previous.rate {
                print("Format changed: \(previous.uid) \(previous.rate) -> \(updated.rate) Hz; stop and rebuild required")
            }
        }
    }
}

func runProbe(_ options: ProbeOptions) throws {
    let inputUnit = try makeUnit(options.input.id, input: true)
    let units = try options.outputs.map { try makeUnit($0.id, input: false) }
    let tones = options.outputs.map { Tone(rate: $0.rate) }
    let meter = Meter(unit: inputUnit)
    defer {
        for unit in units {
            AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit)
        }
        AudioOutputUnitStop(inputUnit)
        AudioUnitUninitialize(inputUnit)
        AudioComponentInstanceDispose(inputUnit)
    }
    try configureInput(inputUnit, meter: meter, rate: options.input.rate)
    for (index, unit) in units.enumerated() {
        try configureOutput(unit, tone: tones[index], rate: options.outputs[index].rate)
    }
    try check(AudioUnitInitialize(inputUnit), "initialize input")
    for unit in units {
        try check(AudioUnitInitialize(unit), "initialize output")
    }
    try check(AudioOutputUnitStart(inputUnit), "start input")
    for unit in units {
        try check(AudioOutputUnitStart(unit), "start output")
    }
    print("Started microphone meter and 440 Hz tone on two outputs for \(options.seconds) s")
    try observe(options, units: units, tones: tones)
    AudioOutputUnitStop(inputUnit)
    print("Microphone frames=\(meter.framesRead) peak=\(meter.peak)")
    for (index, unit) in units.enumerated() {
        AudioOutputUnitStop(unit)
        print("Output \(options.outputs[index].uid) frames=\(tones[index].framesRendered)")
    }
}

do {
    let all = try devices()
    for device in all {
        print("\(device.uid) | \(device.name) | input=\(device.inputs) output=\(device.outputs) rate=\(device.rate)")
    }
    if CommandLine.arguments.dropFirst().first == "probe" {
        try runProbe(parseOptions(CommandLine.arguments, devices: all))
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
