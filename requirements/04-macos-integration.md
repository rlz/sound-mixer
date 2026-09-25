# 04. macOS Integration

## Target system

The first release supports macOS 15 and later. The scaffold builds with Xcode 27.0 and macOS SDK 27.0; the project's minimum version is macOS 15.0. The app works locally without a server. Built React/TypeScript/Tailwind assets are bundled inside the `.app` and loaded in WKWebView through `file://`; no network connection is needed at runtime. Interface changes are first built with `npm run build` in `Web`, then included in the Xcode build.

## Core Audio

- Get input and output device lists and properties through Core Audio HAL; observe list and property changes.
- The native device catalog observes the HAL device list and each device's name, alive state, input/output stream configuration, and nominal sample rate. It publishes refreshed snapshots on the main queue; each snapshot is identified by Core Audio UID and does not treat the device name as an identifier.
- A private aggregate device created for an application tap is an internal capture resource. Exclude its reserved UID prefix from the discoverable device catalog and from physical-input capture, so creating or destroying the tap cannot trigger a device-graph restart.
- At startup, decode and validate saved configuration first, then read the current HAL list and match devices by UID. A missing UID remains in configuration and the interface snapshot but is not passed to the running audio pipeline. A missing device does not make the whole file corrupt.
- After HAL reports a connection or disconnection, reread the list and properties, match UIDs, and publish new state. When a UID matches and the master switch is on, start affected routes after checking format, channels, and permissions. An error in one route does not stop independent routes.
- Run graph stop/start and Core Audio resource creation on a serial audio-control queue. The main thread receives state and meter snapshots asynchronously so an application-tap startup or shutdown cannot block WebKit. Changes to unrelated audio processes do not rebuild the active graph; when a bundle identifier has multiple process objects, select one currently producing output before an idle one.
- Use a native Core Audio pipeline to capture input devices and output to physical devices. Select and verify specific APIs in a two-device prototype before implementation.
- The prototype confirmed enumeration with `kAudioHardwarePropertyDevices` and `AudioObjectGetPropertyData`, channel discovery with `kAudioDevicePropertyStreamConfiguration`, input capture, and two simultaneous outputs with separate HAL Output AudioUnits. Results and limitations: `prototypes/core-audio/README.md`.
- The internal mix uses 48 kHz Float32. Convert sources and outputs with other rates separately; independent output clocks need buffer-fill control and drift compensation. Change the AudioUnit client format after stopping and reinitializing. Handle hardware-format changes and device disconnection by rereading properties and rebuilding the affected pipeline.
- Investigate Core Audio process taps and their aggregate devices for audio from individual applications. Apple documents taps as available from macOS 14.2, which the macOS 15 minimum supports.
- The prototype confirmed one-process capture through a private `CATapDescription` with an explicit process object, `AudioHardwareCreateProcessTap`, a private aggregate device, and an input IOProc. The tap leaves normal app output on (`muteBehavior = .unmuted`); no audio from another process was observed in a control test. Results and verification limits: `prototypes/process-tap/README.md`.
- If the system cannot capture a process or its audio, show that limitation for the application instead of substituting a system-wide mix.
- Discover physical-device main output volume as a Core Audio Float32 scalar from 0 to 1. Prefer the virtual main output-volume property and fall back to the device main volume-scalar property; read the property and check that it is settable before enabling control. Do not synthesize a master control by overwriting individual channel gains or substitute digital gain when neither property is writable. Listen for volume changes and publish them in device snapshots without restarting the audio graph. Set volume on the device-catalog queue and report Core Audio write failures to the bridge.
- When the device exposes a writable main output mute control, setting Device volume to 0 also enables mute; setting it above 0 disables mute. This is required because some devices retain an audible signal at scalar 0. Device volume and mute are live system state, not configuration. Track the pre-change values and last app-set values by stable device UID. On normal exit, stop Sound Mixer output first, then restore each pre-change value only if the device is still available, its property is writable, and its current value still matches the last app-set value. Do not overwrite an externally changed value, persist hardware volume or mute, or change the default system output. Crash exit cannot promise restoration.
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
- Every configured BlackHole stereo-pair output route also appears as an input source for the same pair. Capture those channels through the device's HAL input stream and map the ordered pair to stereo left/right. Check input-side channel availability independently from output-side availability; a route with a valid output pair but unavailable input pair remains an output route and reports its input source as unavailable.
- Detect route channel conflicts before startup. If a device disappears, keep its saved setting but do not output to missing channels.
- Users install the driver using the [official BlackHole instructions](https://github.com/ExistentialAudio/BlackHole#installation-instructions).

## Sources

- The source catalog includes Core Audio input devices and audio-producing application processes. Refresh the process catalog periodically because Core Audio exposes process-list APIs but does not publish a stable application identity; use the bundle identifier as the saved reference and treat the PID as a short-lived runtime handle. Exclude Sound Mixer itself from selectable applications to prevent feedback.
- An application is eligible for capture only while Core Audio reports an output process object and its bundle identifier is available. A catalog entry does not imply that capture permission is granted or that a tap can be created. Preserve distinct permission and runtime failure states per selected source; never substitute a system-wide recording for an unavailable process tap.
- Input permission is requested only when capture of that input is started. System-audio permission is requested by starting the selected process tap. Permission denial is a state of that source and does not stop independent sources.
- `AudioCaptureCoordinator` owns one private process tap and aggregate device per selected application, and one HAL input AudioUnit per selected input UID. Its audio callback reports the source ID, frame count, format, and borrowed buffers synchronously; consumers must process them on the realtime thread without allocation, blocking, logging, file access, or WebKit calls. Capture state changes are published on the main queue. The coordinator is infrastructure for the audio engine; source selection commands and visible permission recovery are not yet wired to the interface.
- Gain-only edits to an active output, virtual bus, or BlackHole route mix must publish new targets to its existing renderer and smooth them per sample. They must not stop/restart capture or output, including capture of devices outside that mix; structural graph edits may rebuild routing. Route renderers identify their mix by route UUID, so routes on the same BlackHole device retain independent gain targets.

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [Apple: AudioHardwareSystem](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)
- [Apple: Requesting Authorization for Media Capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [BlackHole: README](https://github.com/ExistentialAudio/BlackHole/blob/master/README.md)
