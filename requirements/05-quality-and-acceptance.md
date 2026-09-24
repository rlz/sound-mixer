# 05. Quality and Acceptance

## First-release acceptance criteria

1. After launch, every available Core Audio output appears, including devices connected later. Saved outputs, inputs in mixes, and BlackHole routes remain visible as unavailable even if their devices disappeared before launch; they can be removed. When a device with the same UID returns while mixing is on, valid audio resumes without manual configuration.
2. The user can create, rename, and delete an internal bus and add it to another output's mix, but cannot select it as a macOS system device.
3. With BlackHole installed, the user can create stereo routes without selecting channels; the app allocates the lowest available adjacent pair (1/2, 3/4, and so on), and mono routes are not offered. New route names default to `BlackHole {first}/{second}` and can be renamed later. Exhausted pairs and unavailable channels are reported before audio output starts.
4. The user can add an input device, an available application, an internal bus, and a configured BlackHole stereo-pair input to a mix. Each source and the resulting mix have independent levels; changes are audible during playback.
5. For every physical input channel, the user can see a live meter and select Ignore, First, Second, or Both in each destination mix independently; mono defaults to Both and channel 1/2 of stereo defaults to First/Second. Per-channel gains default to linked at unity, can be controlled independently when unlinked, and persist after restart.
6. Cyclic bus references are rejected with a clear error while the active mix keeps working.
7. Permission denial, a missing driver, and device disconnection do not crash the app; their states appear and recover when the cause is resolved.
8. The master switch stops and resumes all mixes. While mixing is off, normal audio from other apps continues through the system output.
9. After a normal Sound Mixer exit, other apps' audio works and app-created taps and audio resources are released. Crash behavior is checked separately.
10. Every accepted configuration change is saved automatically without a Save button. After restart, names, routes, output channels, per-input-channel routing, levels, mute states, and master switch state are restored: a previously Off state stays off; a previously On state starts available routes after validation. A corrupt, invalid, or unsupported-schema file is discarded and replaced by a new empty, disabled configuration; if it cannot be removed, mixing stays off and the user sees an actionable error.
11. Controls work with keyboard and VoiceOver; dark mode and larger system text do not hide primary actions.
12. Build, tests, formatting checks, and linters pass in CI with a supported Xcode version.

## Verification

- Automated tests: models and graph validation reject mono BlackHole route payloads and accept only distinct stereo pairs; audio-engine levels and channels; each physical-input routing choice and gain; linked gain defaults and synchronization, unlink preservation, and re-linking to channel 1; channel meters before gain/routing; multiple source channels summed to the same output; independent maps and gains for two mixes using the same device; BlackHole route input identity and stereo capture; missing input-side channels; confirmed cascade deletion of a route and all source/mute references; preservation on cancellation or failed save; bus/route cycle prevention; invalid-configuration reset; atomic saves; master switch state; bridge message types; and primary interface actions; matching saved and discovered UIDs, missing devices at launch, removal of unavailable settings, reconnection with the same or a different UID, incompatible channels, and disabled mixing. Configuration migration is not required during development.
- Manual Mac checks: built-in speakers, an external output, a microphone, audio from a single application, a multichannel physical input such as Scarlett Solo, multichannel BlackHole, device connection and disconnection, permission revocation, disabled mixing, normal and crash exits, and restart after each setting change. For BlackHole, create several routes without choosing channels and confirm automatic allocation uses 1/2, 3/4, 5/6 in order, that the same named pairs appear under Inputs, capture and mix loopback from each pair, and that exhausted or input-unavailable pairs remain clearly unavailable. For a multichannel physical input, verify every reported channel can be ignored, sent to First, Second, or Both; verify different mixes can use different maps; and reconnect after a channel-count change to confirm saved entries and new-channel defaults. Separately check startup without a previously configured output, input, and BlackHole device; removal of each unavailable item; and reconnection of the same device with mixing both on and off.
- Meter checks: compare input, per-source mix, and destination meters against known silence and reference tones; confirm source gain, mix master gain, limiter behavior, and global mute affect only the specified meter locations; confirm stale/inactive readings clear after capture stops or a device disconnects; verify meter updates stay at or below 15 Hz and do not cause audio callback allocations, locks, or UI stalls.
- During audio checks, measure latency, buffer underruns, and CPU load using a predefined reference configuration. Set target thresholds after the prototype and record them here.

## Acceptance limits

Manual checks requiring installed BlackHole or multiple physical devices cannot be marked complete based only on unit tests. Record results and test Mac details in a verification report before release.

## Built-in microphone regression — September 24, 2026

- Environment: macOS 27.0 (26A428), Xcode 27.0, built-in input reporting 44.1 kHz and one channel. A standalone diagnostic compiled the production capture coordinator, input session, and peak meter. It ran capture for three seconds, stored no audio, and started no output.
- Baseline: the fixed 48 kHz stereo input client format started successfully, but 259 callbacks returned `AudioUnitRender` status -10863. No frames reached the meter, reproducing Capturing together with Inactive.
- Corrected format: using the device's input stream rate and mono channel count produced 258 successful callbacks and 132,096 delivered frames, with render status 0 and a fresh peak of approximately 0.0121.
- Final production source check: 132,096 delivered frames, fresh peak approximately 0.0116, and runtime capture health Capturing. The callback counter used for the baseline was diagnostic instrumentation; the final check used the unmodified production session and counted delivered frames at its consumer.
- The web and native app build passed. SwiftLint passed for the affected audio files. This verifies live native microphone capture and metering, not the complete window flow, signed-app permission denial, or device reconnection; those checks remain pending.
