# 04. macOS Integration

## Target system

The first release supports macOS 15 and later. The scaffold builds with Xcode 27.0 and macOS SDK 27.0; the project's minimum version is macOS 15.0. The app works locally without a server. Built React/TypeScript/Tailwind assets are bundled inside the `.app` and loaded in WKWebView through `file://`; no network connection is needed at runtime. Interface changes are first built with `npm run build` in `Web`, then included in the Xcode build.

## Core Audio

- Get input and output device lists and properties through Core Audio HAL; observe list and property changes.
- At startup, decode and validate saved configuration first, then read the current HAL list and match devices by UID. A missing UID remains in configuration and the interface snapshot but is not passed to the running audio pipeline. A missing device does not make the whole file corrupt.
- After HAL reports a connection or disconnection, reread the list and properties, match UIDs, and publish new state. When a UID matches and the master switch is on, start affected routes after checking format, channels, and permissions. An error in one route does not stop independent routes.
- Use a native Core Audio pipeline to capture input devices and output to physical devices. Select and verify specific APIs in a two-device prototype before implementation.
- The prototype confirmed enumeration with `kAudioHardwarePropertyDevices` and `AudioObjectGetPropertyData`, channel discovery with `kAudioDevicePropertyStreamConfiguration`, input capture, and two simultaneous outputs with separate HAL Output AudioUnits. Results and limitations: `prototypes/core-audio/README.md`.
- The internal mix uses 48 kHz Float32. Convert sources and outputs with other rates separately; independent output clocks need buffer-fill control and drift compensation. Change the AudioUnit client format after stopping and reinitializing. Handle hardware-format changes and device disconnection by rereading properties and rebuilding the affected pipeline.
- Investigate Core Audio process taps and their aggregate devices for audio from individual applications. Apple documents taps as available from macOS 14.2, which the macOS 15 minimum supports.
- The prototype confirmed one-process capture through a private `CATapDescription` with an explicit process object, `AudioHardwareCreateProcessTap`, a private aggregate device, and an input IOProc. The tap leaves normal app output on (`muteBehavior = .unmuted`); no audio from another process was observed in a control test. Results and verification limits: `prototypes/process-tap/README.md`.
- If the system cannot capture a process or its audio, show that limitation for the application instead of substituting a system-wide mix.
- Configured outputs do not automatically become system outputs. Selecting a system output remains a user action in macOS unless a separate feature is designed later.
- When mixing is turned off or the app exits normally, stop IO, remove process-created taps and aggregate devices, and release devices. For a crash, verify with a prototype that the system releases process-tap resources and normal playback is not left muted.
- `prototypes/process-tap/lifecycle.sh` confirmed normal resource deletion by UID and an unchanged system output when turned off. After `SIGKILL`, the same external process kept running and a new tap captured its audio again. A listening check on September 23, 2026 confirmed an uninterrupted tone on system output when capture stopped and after the prototype was killed. Another process cannot directly enumerate the terminated process's private resources. Capture after a crash may need a short wait for audio-service cleanup. Test the finished app separately during acceptance.

## Permissions

- Request microphone access on first use of an input device that needs it. Include `NSMicrophoneUsageDescription` in Info.plist.
- For process taps, include `NSAudioCaptureUsageDescription` and request system-audio recording permission when starting the relevant source.
- Denial does not block other routes; the interface explains exactly which sources are unavailable.
- Do not request screen access just for audio unless the selected and verified API requires it.

## BlackHole

- BlackHole is an external driver. Discover installed instances and their actual output channel counts through Core Audio.
- Available BlackHole builds may have different channel counts; the interface must not assume a fixed layout.
- For selected channels, use one HAL Output AudioUnit per device with a full-output-channel, interleaved Float32 client buffer. Zero unused channels and combine independent routes in that buffer before output. A BlackHole 64ch loopback test confirmed mono channel 17 and stereo pairs 3–4 and 63–64 without signal in the other channels; results and code are in `prototypes/channel-routing/`.
- Detect route channel conflicts before startup. If a device disappears, keep its saved setting but do not output to missing channels.
- Users install the driver using the [official BlackHole instructions](https://github.com/ExistentialAudio/BlackHole#installation-instructions).

## Sources

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [Apple: AudioHardwareSystem](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)
- [Apple: Requesting Authorization for Media Capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [BlackHole: README](https://github.com/ExistentialAudio/BlackHole/blob/master/README.md)
