# Core Audio HAL Verification

The prototype runs separately from the app and does not change the system output or a device's nominal sample rate. It lists device UIDs and channel counts, captures one input and measures its signal level, and simultaneously plays a quiet 440 Hz test tone through two different stereo outputs. An optional flag stops both outputs, changes their client format, and starts them again.

```bash
bash prototypes/core-audio/run.sh
bash prototypes/core-audio/run.sh probe --input BuiltInMicrophoneDevice \
    --outputs BuiltInSpeakerDevice BlackHole2ch_UID --seconds 5 \
    --switch-client-rate 44100
```

The example UIDs belong only to the tested Mac. On another Mac, run the command without arguments first and substitute discovered UIDs. Grant microphone permission to the process running the prototype for input capture. The output tone has amplitude 0.05; check speaker volume before running it. The binary is built in `.build/`.

Formatting and lint commands: `.tools/bin/swiftformat prototypes/core-audio/main.swift --lint --config prototypes/core-audio/.swiftformat --cache ignore` and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer .tools/bin/swiftlint lint --strict --no-cache --config .swiftlint.yml prototypes/core-audio/main.swift`.

## Verified on September 23, 2026

Environment: macOS 27.0, Xcode 27.0, MacBook Air; Swift CLI running with access to audio devices. Without that access, the environment returned an empty device list, so the results below were collected with access granted.

- `kAudioHardwarePropertyDevices` and `AudioObjectGetPropertyData` returned devices and their UIDs. `kAudioDevicePropertyStreamConfiguration` distinguished input and output channels: built-in microphone 1 input / 0 outputs, built-in speakers 0 / 2, and BlackHole 2ch 2 / 2. The microphone's nominal rate was 44.1 kHz and both selected outputs were 48 kHz. A discovered Multi-Output Device had 0 / 0 channels and 0 Hz; its name alone cannot establish that it is an available output.
- `kAudioUnitSubType_HALOutput`, `kAudioOutputUnitProperty_EnableIO`, `kAudioOutputUnitProperty_CurrentDevice`, `kAudioOutputUnitProperty_SetInputCallback`, and `AudioUnitRender` worked for the built-in microphone: 227,328 frames arrived in 5 seconds with a 0.065 peak. The measured level depends on nearby sound.
- Two separate HAL Output AudioUnits with `kAudioUnitProperty_SetRenderCallback` concurrently processed 238,119 frames on built-in speakers and 237,220 on BlackHole. Callbacks and frame processing were verified; audible playback and reading the signal from BlackHole output were not.
- Both outputs' client `kAudioUnitProperty_StreamFormat` changed from 48 to 44.1 kHz after stop, `AudioUnitUninitialize`, format setting, `AudioUnitInitialize`, and restart. `AudioUnitGetProperty` confirmed 44.1 kHz. Device nominal rates remained 48 kHz. This verifies *client* format changes; an external hardware-format change during operation was not tested.

## Decision for the main audio pipeline

The internal stereo mix runs at 48 kHz Float32. Convert each input to this format before summing and each output to its device format. Do not treat the AudioUnit client format as the hardware format: read `kAudioDevicePropertyNominalSampleRate` and the actual `kAudioUnitProperty_StreamFormat` separately. Independent devices need separate output callbacks and buffers; their clocks may drift even with the same nominal 48 kHz rate. The connection between a mix and an output therefore needs a buffer with fill-level control and drift compensation during resampling. Choose specific latency, buffer size, and compensation algorithm after measurements in the audio-engine task.

The prototype does not route the microphone to the outputs: it independently checks the input and two test-tone outputs. It does not verify audibility, dynamic hardware-format changes, reconnection, permission after denial, or long-term drift. These cases remain in integration tasks and the acceptance matrix. On a hardware-format change, the production pipeline must stop the affected AudioUnit, reread device properties, rebuild conversion, and restart the route or show an error; this transition needs separate verification.
