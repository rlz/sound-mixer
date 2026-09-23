# Core Audio Process Tap Verification

The prototype lists Core Audio process objects, captures stereo audio from one process by PID, and measures peak level. It creates a private tap with `muteBehavior = .unmuted`, a private aggregate device, and an input IOProc. It does not change the system output or volume. On capture shutdown, it removes the IOProc, aggregate device, and tap in reverse order.

```bash
bash prototypes/process-tap/run.sh list
bash prototypes/process-tap/run.sh self-check
bash prototypes/process-tap/run.sh capture PID --seconds 10
bash prototypes/process-tap/run.sh cycle PID --seconds 10
bash prototypes/process-tap/lifecycle.sh
SOUND_MIXER_LISTENING_MODE=1 bash prototypes/process-tap/lifecycle.sh
```

Play audio in the target application, find its PID with `list`, and start `capture`. The prototype rejects its own PID. If the process does not appear in Core Audio, start playback and list again. Capture may require macOS **System Audio Recording** permission for the process running the prototype. The main app already includes `NSAudioCaptureUsageDescription`; test the first prompt and denial separately in a signed app build.

`cycle` stops capture, destroys the IOProc, private aggregate device, and tap, then checks by UID that these resources are gone and the system output is unchanged. `lifecycle.sh` creates a quiet test signal and starts `afplay`, checks `cycle`, forcibly kills only the prototype with `SIGKILL`, and captures the same process again. Run this scenario on a Mac with access to audio services; in the restricted environment, Core Audio returns an empty process list and system output `0`. You can listen to the system output during the scenario: the test sound should continue when capture stops and after `SIGKILL`.

For a listening check, `SOUND_MIXER_LISTENING_MODE=1` raises the test tone level and prints the verification stages. The tone should remain continuous through the scenario; the script does not change system volume.

The binary is built in `prototypes/process-tap/.build/`. Linting and formatting use `prototypes/core-audio/.swiftformat`.

## Verified on September 23, 2026

Environment: macOS 27.0, Xcode 27.0, MacBook Air. The prototype ran outside the restricted command environment to access audio services. In the restricted environment, the process-object list was empty; with access granted, it listed PID, AudioObjectID, bundle ID, and output state for 25 processes. This is a list of processes connected to Core Audio, not a catalog of all running applications.

- `AudioHardwareCreateProcessTap` with `CATapDescription(stereoMixdownOfProcesses: [process])` and `muteBehavior = .unmuted` created a tap for one `afplay` process. Over 4 seconds, a private aggregate device with `kAudioAggregateDeviceTapListKey` and an input `AudioDeviceIOProc` received 190,464 frames while a quiet 440 Hz tone played; the Float32 peak was 0.02136. The format was checked before reading: stereo Float32 PCM, 48 kHz.
- While another `afplay` played a tone, the tap for a process playing silence received 191,488 frames with a peak of 0. This confirms no audio from the other process leaked into the capture in this test. `self-check` confirmed rejection of the prototype's own PID.
- All IOProc, aggregate-device, and tap destruction calls returned `noErr`. System-audio recording permission already allowed capture in this environment; the first system prompt, denial, and subsequent permission grant were not tested.

A process tap must use an explicit list of selected process objects and exclude the Sound Mixer process. Each source needs its own availability and error state. Do not replace an unavailable process with a global tap. Audio from a selected process through this API may depend on its actual audio route and system limitations; the prototype checked only `afplay` and the current output.

## Lifecycle verification on September 23, 2026

On the same Mac, `lifecycle.sh` passed: when capture stopped, destruction of the IOProc, aggregate device, and tap returned `noErr`; lookup of private resources by UID returned `kAudioObjectUnknown`; system output remained `108`. The `afplay` process kept running. After killing the prototype with `SIGKILL`, a new tap for the same `afplay` received about 95,000 frames with a 0.001526 peak at 48 kHz, and system output remained `108`. The new tap received the same local AudioObjectIDs (`179` and `180`) as the tap before termination.

On the first run after `SIGKILL`, immediate recapture once failed to find the newly created aggregate device by UID; on the next run, recapture worked on the first attempt. The scenario allows up to ten retries one second apart and reports an explicit error if recovery fails.

Another process cannot see private taps and aggregate devices through system lists or UID translation. Their absence after `SIGKILL` therefore cannot be proved directly by such a query; creating a new tap and capturing audio confirms operational recovery in the tested scenario. The automated test does not measure audibility on the physical output; confirm it by listening on a Mac during app acceptance checks.

A listening check on the same Mac on September 23, 2026 used `SOUND_MIXER_LISTENING_MODE=1` to play a 440 Hz tone through Core Audio system output `107`. A listener confirmed uninterrupted sound when capture stopped normally, after the prototype was killed with `SIGKILL`, and during recapture. The script confirmed that `afplay` remained active, system output did not change, and a new tap received 95,232 frames with a 0.04578 peak on the first attempt. This confirms audibility in the tested prototype scenario; acceptance testing of the finished app remains a separate task.

Reference: [Apple, Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps).
