import AudioToolbox
import CoreAudio
import Foundation

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
        throw NSError(domain: "ProcessTapProbe", code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "\(action): OSStatus \(status)"
        ])
    }
}

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as _: T.Type) throws -> T {
    var propertyAddress = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
    defer { pointer.deallocate() }
    try check(AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, pointer), "read property \(selector)")
    return pointer.load(as: T.self)
}

func processIDs() throws -> [AudioObjectID] {
    var propertyAddress = address(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    try check(AudioObjectGetPropertyDataSize(system, &propertyAddress, 0, nil, &size), "process list size")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !ids.isEmpty else { return [] }
    try ids.withUnsafeMutableBytes { bytes in
        try check(AudioObjectGetPropertyData(system, &propertyAddress, 0, nil, &size, bytes.baseAddress!), "process list")
    }
    return ids
}

func processObject(for pid: pid_t) throws -> AudioObjectID {
    var propertyAddress = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var result = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        UInt32(MemoryLayout<pid_t>.size),
        &qualifier,
        &size,
        &result
    ), "translate PID")
    return result
}

func listProcesses() throws {
    print("Audio processes (self PID \(getpid()) excluded from capture):")
    for id in try processIDs() {
        let pid: pid_t = try value(id, kAudioProcessPropertyPID, as: pid_t.self)
        let bundle: CFString? = try? value(id, kAudioProcessPropertyBundleID, as: CFString.self)
        let running: UInt32 = (try? value(id, kAudioProcessPropertyIsRunningOutput, as: UInt32.self)) ?? 0
        print("PID \(pid), object \(id), output \(running != 0), bundle \(bundle.map { $0 as String } ?? "-")")
    }
}

func objectForUID(_ uid: CFString, selector: AudioObjectPropertySelector) throws -> AudioObjectID {
    var propertyAddress = address(selector)
    var qualifier = uid
    var result = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    try withUnsafePointer(to: &qualifier) { pointer in
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            UInt32(MemoryLayout<CFString>.size),
            pointer,
            &size,
            &result
        ), "translate UID")
    }
    return result
}

func defaultOutput() throws -> AudioObjectID {
    try value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
}

func resourceIDs(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
    var propertyAddress = address(selector)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    try check(AudioObjectGetPropertyDataSize(system, &propertyAddress, 0, nil, &size), "resource list size")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !ids.isEmpty else { return [] }
    try ids.withUnsafeMutableBytes { bytes in
        try check(AudioObjectGetPropertyData(system, &propertyAddress, 0, nil, &size, bytes.baseAddress!), "resource list")
    }
    return ids
}

func listResources() throws {
    try print("Default output: \(defaultOutput())")
    try print("Tap IDs: \(resourceIDs(kAudioHardwarePropertyTapList))")
}

final class Meter {
    var frames: UInt64 = 0
    var peak: Float = 0
}

let inputCallback: AudioDeviceIOProc = { _, _, input, _, _, _, context in
    guard let context else { return kAudio_ParamError }
    let meter = Unmanaged<Meter>.fromOpaque(context).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    for buffer in buffers {
        guard let data = buffer.mData else { continue }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let samples = data.assumingMemoryBound(to: Float.self)
        for index in 0 ..< count {
            meter.peak = max(meter.peak, abs(samples[index]))
        }
        meter.frames += UInt64(count / max(1, Int(buffer.mNumberChannels)))
    }
    return noErr
}

func checkedTapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
    let format: AudioStreamBasicDescription = try value(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
    guard format.mFormatID == kAudioFormatLinearPCM,
          format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
          format.mBitsPerChannel == 32,
          format.mChannelsPerFrame == 2
    else {
        throw NSError(domain: "ProcessTapProbe", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Unsupported tap format; expected stereo Float32 PCM"
        ])
    }
    return format
}

func aggregateDescription(tapUID: CFString, aggregateUID: CFString) -> CFDictionary {
    [
        kAudioAggregateDeviceNameKey: "Sound Mixer process tap probe",
        kAudioAggregateDeviceUIDKey: aggregateUID as String,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID as String]],
        kAudioAggregateDeviceTapAutoStartKey: true
    ] as CFDictionary
}

func capture(pid: pid_t, seconds: Int) throws -> (CFString, CFString) {
    guard pid != getpid() else { throw NSError(domain: "ProcessTapProbe", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Refusing to capture this probe's own PID"
    ]) }
    let process = try processObject(for: pid)
    guard process != kAudioObjectUnknown else { throw NSError(domain: "ProcessTapProbe", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "PID \(pid) has no Core Audio process object; start playback and list again"
    ]) }

    let description = CATapDescription(stereoMixdownOfProcesses: [process])
    description.name = "Sound Mixer process tap probe"
    description.isPrivate = true
    description.muteBehavior = .unmuted
    var tap = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
    defer { let status = AudioHardwareDestroyProcessTap(tap); print("destroy tap: \(status)") }

    let format = try checkedTapFormat(tap)

    let uid: CFString = try value(tap, kAudioTapPropertyUID, as: CFString.self)
    guard try objectForUID(uid, selector: kAudioHardwarePropertyTranslateUIDToTap) == tap else {
        throw NSError(domain: "ProcessTapProbe", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Created tap cannot be found by UID"
        ])
    }
    let aggregateUID = UUID().uuidString as CFString
    var aggregate = AudioObjectID(kAudioObjectUnknown)
    try check(
        AudioHardwareCreateAggregateDevice(aggregateDescription(tapUID: uid, aggregateUID: aggregateUID), &aggregate),
        "create aggregate device"
    )
    defer { let status = AudioHardwareDestroyAggregateDevice(aggregate); print("destroy aggregate: \(status)") }
    guard try objectForUID(aggregateUID, selector: kAudioHardwarePropertyTranslateUIDToDevice) == aggregate else {
        throw NSError(domain: "ProcessTapProbe", code: 8, userInfo: [
            NSLocalizedDescriptionKey: "Created aggregate cannot be found by UID"
        ])
    }

    let meter = Meter()
    var callbackID: AudioDeviceIOProcID?
    try check(AudioDeviceCreateIOProcID(aggregate, inputCallback, Unmanaged.passUnretained(meter).toOpaque(), &callbackID), "create IOProc")
    guard let callbackID else { throw NSError(domain: "ProcessTapProbe", code: 3) }
    defer { let status = AudioDeviceDestroyIOProcID(aggregate, callbackID); print("destroy IOProc: \(status)") }
    try check(AudioDeviceStart(aggregate, callbackID), "start capture (grant System Audio Recording if prompted)")
    print(
        "Capturing PID \(pid), process object \(process), tap \(tap), aggregate \(aggregate), " +
            "\(format.mSampleRate) Hz for \(seconds)s. Play audio in the target app."
    )
    print("Tap UID: \(uid); aggregate UID: \(aggregateUID)")
    fflush(stdout)
    Thread.sleep(forTimeInterval: TimeInterval(seconds))
    try check(AudioDeviceStop(aggregate, callbackID), "stop capture")
    print("Captured frames: \(meter.frames); peak: \(meter.peak)")
    return (uid, aggregateUID)
}

func cycle(pid: pid_t, seconds: Int) throws {
    let outputBefore = try defaultOutput()
    print("Default output before cycle: \(outputBefore)")
    let (tapUID, aggregateUID) = try capture(pid: pid, seconds: seconds)
    // Returning from capture runs all cleanup defers before the off-state checks.
    Thread.sleep(forTimeInterval: 0.5)
    let tapAfter = try objectForUID(tapUID, selector: kAudioHardwarePropertyTranslateUIDToTap)
    let aggregateAfter = try objectForUID(aggregateUID, selector: kAudioHardwarePropertyTranslateUIDToDevice)
    let outputAfter = try defaultOutput()
    print("Off state: tap \(tapAfter), aggregate \(aggregateAfter), default output \(outputAfter)")
    guard tapAfter == kAudioObjectUnknown, aggregateAfter == kAudioObjectUnknown, outputAfter == outputBefore else {
        throw NSError(domain: "ProcessTapProbe", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Off state retained an audio resource or changed the default output"
        ])
    }
    print("Off-state resource check passed")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args == ["list"] {
        try listProcesses()
    } else if args == ["resources"] {
        try listResources()
    } else if args == ["self-check"] {
        do {
            _ = try capture(pid: getpid(), seconds: 1)
            throw NSError(domain: "ProcessTapProbe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Self-capture was accepted"])
        } catch let error as NSError where error.domain == "ProcessTapProbe" && error.code == 1 {
            print("Self-capture rejected as expected")
        }
    } else if args.first == "capture" {
        guard args.count == 4 else {
            print("Usage: run.sh capture PID --seconds 10")
            exit(2)
        }
        guard let pid = pid_t(args[1]), args[2] == "--seconds" else {
            print("Usage: run.sh capture PID --seconds 10")
            exit(2)
        }
        guard let seconds = Int(args[3]), (1 ... 120).contains(seconds) else {
            print("Usage: run.sh capture PID --seconds 10")
            exit(2)
        }
        _ = try capture(pid: pid, seconds: seconds)
    } else if args.first == "cycle" {
        guard args.count == 4, let pid = pid_t(args[1]), args[2] == "--seconds",
              let seconds = Int(args[3]), (1 ... 120).contains(seconds)
        else {
            print("Usage: run.sh cycle PID --seconds 10")
            exit(2)
        }
        try cycle(pid: pid, seconds: seconds)
    } else {
        print("Usage: run.sh [list | resources | self-check | capture PID --seconds 10 | cycle PID --seconds 10]")
        exit(2)
    }
} catch {
    fputs("Process tap probe: \(error.localizedDescription)\n", stderr)
    exit(1)
}
