# 05. Quality and Acceptance

## First-release acceptance criteria

1. After launch, every available Core Audio output appears, including devices connected later. Saved outputs, inputs in mixes, and BlackHole routes remain visible as unavailable even if their devices disappeared before launch; they can be removed. When a device with the same UID returns while mixing is on, valid audio resumes without manual configuration.
2. The user can create, rename, and delete an internal bus and add it to another output's mix, but cannot select it as a macOS system device.
3. With BlackHole installed, the user can create a route using a selected channel pair. Conflicting or missing channels are detected before audio output starts.
4. The user can add an input device, an available application, and an internal bus to a mix. Each source and the resulting mix have independent levels; changes are audible during playback.
5. Mono audio can be sent to the left, right, or both channels, and the mode persists after restart.
6. Cyclic bus references are rejected with a clear error while the active mix keeps working.
7. Permission denial, a missing driver, and device disconnection do not crash the app; their states appear and recover when the cause is resolved.
8. The master switch stops and resumes all mixes. While mixing is off, normal audio from other apps continues through the system output.
9. After a normal Sound Mixer exit, other apps' audio works and app-created taps and audio resources are released. Crash behavior is checked separately.
10. Every accepted configuration change is saved automatically without a Save button. After restart, names, routes, channels, levels, mute states, and master switch state are restored: a previously Off state stays off; a previously On state starts available routes after validation. A corrupt, invalid, or unsupported-schema file is discarded and replaced by a new empty, disabled configuration; if it cannot be removed, mixing stays off and the user sees an actionable error.
11. Controls work with keyboard and VoiceOver; dark mode and larger system text do not hide primary actions.
12. Build, tests, formatting checks, and linters pass in CI with a supported Xcode version.

## Verification

- Automated tests: models and graph validation, audio-engine levels and channels, invalid-configuration reset, atomic saves, master switch state, bridge message types, and primary interface actions; matching saved and discovered UIDs, missing devices at launch, removal of unavailable settings, reconnection with the same or a different UID, incompatible channels, and disabled mixing. Configuration migration is not required during development.
- Manual Mac checks: built-in speakers, an external output, a microphone, audio from a single application, multichannel BlackHole, device connection and disconnection, permission revocation, disabled mixing, normal and crash exits, and restart after each setting change. Separately check startup without a previously configured output, input, and BlackHole device; removal of each unavailable item; and reconnection of the same device with mixing both on and off.
- Meter checks: compare input, per-source mix, and destination meters against known silence and reference tones; confirm source gain, mix master gain, limiter behavior, and global mute affect only the specified meter locations; confirm stale/inactive readings clear after capture stops or a device disconnects; verify meter updates stay at or below 15 Hz and do not cause audio callback allocations, locks, or UI stalls.
- During audio checks, measure latency, buffer underruns, and CPU load using a predefined reference configuration. Set target thresholds after the prototype and record them here.

## Acceptance limits

Manual checks requiring installed BlackHole or multiple physical devices cannot be marked complete based only on unit tests. Record results and test Mac details in a verification report before release.
