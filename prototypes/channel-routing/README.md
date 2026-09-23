# BlackHole Channel Output Verification

The prototype lists Core Audio devices by UID and input/output channel count. The `probe` command creates a HAL Output AudioUnit with an interleaved Float32 client format covering the device's **full output channel count**. Its callback zeros the whole buffer, then writes a quiet 440 Hz tone with amplitude 0.02 to either one selected channel or two distinct channels. If input and output channel counts match, a second HAL AudioUnit reads the input and checks each channel's peak level. The system output and hardware volume are not changed.

```bash
bash prototypes/channel-routing/run.sh list
bash prototypes/channel-routing/run.sh probe BlackHole64ch_UID 3,4 3
bash prototypes/channel-routing/run.sh probe BlackHole64ch_UID 17 2
```

The example UID and channel count belong only to the tested Mac. Command channel numbers start at 1; callback indices start at 0. A mono route uses one channel, and a stereo route uses two distinct channels. Before starting the AudioUnit, the prototype checks the requested range against the device's actual channel count. For a device without a corresponding input, the prototype verifies the output callback but cannot measure the physical signal.

The prototype writes all channels of **one** device through one output AudioUnit. For several routes to the same device, the production engine must combine their samples in one full buffer. Overlapping channel assignments are checked before starting the graph. The base mix for a BlackHole device currently reserves every channel; although this prototype proves subset selection is possible, the interface does not yet specify channel-selection behavior for the base mix.

## Verified on September 23, 2026

Environment: macOS 27.0, Xcode 27.0, BlackHole 64ch (`BlackHole64ch_UID`), 64 input and 64 output channels, 48 kHz. The prototype ran outside the restricted command environment to access audio services. Before the installed BlackHole variant was replaced, this Mac showed BlackHole 2ch; the example UID is therefore not constant across installations.

- Stereo pair 3–4: the output callback processed 144,384 frames in 3 seconds. The BlackHole input received 145,920 frames; channels 3 and 4 peaked at 0.02, and all other 62 channels at 0.
- Stereo pair 63–64: the output callback processed 96,256 frames in 2 seconds. The input received 98,304 frames; channels 63 and 64 peaked at 0.02, and the others at 0. This checks the upper bound of the channel range.
- Mono channel 17: the output callback processed 96,256 frames in 2 seconds. The input received 98,304 frames; channel 17 peaked at 0.02, and the others at 0.

This verifies writing to and loopback capture from selected BlackHole 64ch channels. It does not measure latency, audible hardware output, simultaneous mixing of several routes, or behavior on device disconnection or format change. Those cases remain in the engine and acceptance tasks.
