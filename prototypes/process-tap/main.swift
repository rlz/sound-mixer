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

func capture(pid: pid_t, seconds: Int) throws {
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

    let uid: CFString = try value(tap, kAudioTapPropertyUID, as: CFString.self)
    let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Sound Mixer process tap probe",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid as String]],
        kAudioAggregateDeviceTapAutoStartKey: true
    ]
    var aggregate = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "create aggregate device")
    defer { let status = AudioHardwareDestroyAggregateDevice(aggregate); print("destroy aggregate: \(status)") }

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
    Thread.sleep(forTimeInterval: TimeInterval(seconds))
    try check(AudioDeviceStop(aggregate, callbackID), "stop capture")
    print("Captured frames: \(meter.frames); peak: \(meter.peak)")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args == ["list"] {
        try listProcesses()
    } else if args == ["self-check"] {
        do {
            try capture(pid: getpid(), seconds: 1)
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
        try capture(pid: pid, seconds: seconds)
    } else {
        print("Usage: run.sh [list | self-check | capture PID --seconds 10]")
        exit(2)
    }
} catch {
    fputs("Process tap probe: \(error.localizedDescription)\n", stderr)
    exit(1)
}
