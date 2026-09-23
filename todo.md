# Development Plan

Statuses: `[ ]` = not started, `[~]` = in progress, `[x]` = complete. Tasks are listed in dependency order. Each task has a verifiable result.

## 0. Research and scaffold

- [x] Define scenarios, terminology, architecture boundaries, and acceptance criteria in `README.md`, `AGENTS.md`, and `requirements/`.
- [x] Create the macOS 15+ Xcode app project, WebKit shell, and React/TypeScript/Tailwind project. **Done when:** a clean build opens a window with the local interface without network access.
- [x] Set up SwiftFormat, SwiftLint, Prettier, ESLint, and CI with four-space indentation. **Done when:** the same checks run locally and in CI, and tool versions are pinned.
- [x] Make English the default application language. **Done when:** current interface text, load errors, and permission prompts are in English; the HTML language and macOS development language are set to English.
- [x] Prototype Core Audio input and output discovery, microphone capture, output to two devices, and format changes. **Done when:** working APIs, measurements, limitations, and the sample-rate decision are documented in `prototypes/core-audio/README.md`. Client-format switching was verified; external hardware-format changes remain for integration testing.
- [x] Prototype process taps on a supported macOS version: process listing, permission, audio from one application, and prevention of self-capture. **Done when:** a runnable prototype and verified limitations are documented. The first permission prompt and denial remain for integration testing in a signed app.
- [x] Check audio behavior and tap cleanup when mixing is disabled and when the prototype exits normally or crashes. **Done when:** `prototypes/process-tap/lifecycle.sh` passes; a listener confirms uninterrupted system-output audio when capture stops and after `SIGKILL`. Limitations are documented.
- [x] Check BlackHole on a multichannel device and how to write to a selected channel pair. **Done when:** a reproducible prototype and conclusions about valid channel layouts are documented. BlackHole 64ch loopback confirmed mono channel 17 and stereo pairs 3–4 and 63–64 by reading all 64 channels.

## 1. Domain model and storage

- [x] Define models for devices, buses, routes, sources, and levels, stable identifiers, and the configuration schema. **Done when:** serialization tests cover the models.
- [x] Extend configuration to v2 with last-known-name metadata for configured UIDs. **Done when:** a device missing at startup can be labeled with its saved name; a UID without a name is shown as the UID. Older development schemas are rejected; migration is not required before release.
- [x] Implement graph validation for node existence, cycles, BlackHole channel conflicts, and format compatibility. **Done when:** tests reject invalid changes before application. Structural validation and per-endpoint runtime device checks are covered by tests.
- [x] Implement automatic atomic saving of every accepted change, including the master switch state, with schema version checks. **Done when:** configuration is restored after restart without manual saving; changes to last-known names and removal of the last reference to a UID are saved; a corrupt or unsupported file is handled without a crash. The native configuration store is wired into startup; future edit entry points must use its transaction API.

## 2. Native audio pipeline

- [x] Observe Core Audio inputs and outputs and their availability. **Done when:** the list updates without restarting, and settings are tied to UIDs. The native device catalog observes HAL list and relevant device-property changes and publishes UID-keyed snapshots; the interface bridge will consume these snapshots in the interface task.
- [x] Show a read-only list of discovered Core Audio outputs in the app. **Done when:** the native snapshot populates device names, UIDs, output channel counts, availability, and updates after device changes; no sample devices are shown. This is the visible checkpoint before returning to the remaining core work.
- [x] Match saved UIDs to discovered devices at launch and on every HAL change. **Done when:** a saved output, input, or BlackHole route remains unavailable if its device is missing at startup; absence does not corrupt configuration or block independent routes; the state snapshot distinguishes saved and discovered devices. The native snapshot now unions all configured UIDs with current Core Audio devices and reports their saved roles, live presence, availability, channel counts, and best-known name. Audio resumption remains part of the engine and reconnection tasks.
- [~] Capture input devices and application sources with permission handling. **Done when:** sources produce separate streams and denial appears as a source state. Input-device discovery is available; output-producing applications are listed by bundle identifier with transient PIDs excluded from persistence. `AudioCaptureCoordinator` now owns independent HAL input and process-tap sessions, streams buffers with per-source state, and releases resources on shutdown. UI commands, deterministic TCC denial mapping, and signed-app permission verification remain.
- [ ] Implement the stereo mixing engine, source and master levels, smooth level changes, and clipping protection. **Done when:** audio tests verify levels, absence of clicks, and basic stability.
- [ ] Add mono routing to the left, right, or both channels. **Done when:** tests verify expected samples in both channels.
- [ ] Implement internal virtual buses and safe replacement of the active graph. **Done when:** multiple mixes can use one bus and a cycle cannot start.
- [ ] Output to physical devices and BlackHole routes with channel selection. **Done when:** independent mixes play on selected outputs and overlapping channels are rejected.
- [ ] Handle device disconnection, reconnection, and format changes. **Done when:** the same UID resumes valid audio automatically while mixing is on, after format, channel, and permission checks; a different UID does not replace it, and the off switch does not start audio.
- [ ] Implement the master switch and release audio resources when switching off or exiting. **Done when:** all mixes stop and resume, and normal audio from other apps works after Sound Mixer exits.
- [ ] Start from saved state after validating the graph, devices, and permissions. **Done when:** saved Off does not start the audio pipeline; saved On starts available routes and reports the others.

## 3. Interface and integration

- [~] Implement a typed Swift ↔ WebKit bridge, command validation, and state snapshots. **Done when:** an invalid command is rejected without changing the audio graph. Initial snapshots and validated persistence commands are implemented; native audio graph application and end-to-end rejection verification remain with the audio engine.
- [x] Add Font Awesome Free to the React interface for local SVG bundling. **Done when:** package versions are pinned, an icon appears on the current screen, and the build needs no CDN.
- [ ] Build the left panel with device, bus, and BlackHole groups, selection, and sliders. **Done when:** all outputs appear and sliders control the native mix.
- [ ] Add the master switch and a textual disabled state to the window. **Done when:** the state is keyboard accessible, confirmed by Swift, and restored at launch.
- [ ] Add creation, renaming, and deletion of virtual buses and BlackHole routes, with channel selection. **Done when:** these flows work with validation errors and state restoration.
- [ ] Build the right panel with the source catalog, mix rows, levels, and mono input placement. **Done when:** a user can assemble a mix without editing files.
- [ ] Allow removal of a saved mix for a missing output and removal of a missing input from a mix. **Done when:** these actions work after startup without the devices; deletion updates and saves configuration without affecting Core Audio; an unconfigured available output remains listed.
- [ ] Show permission states, missing devices, missing BlackHole, and route errors. **Done when:** saved items remain visible after startup without their devices, show a name or UID and an unavailability reason, and can be removed; reconnection updates state without reopening the window.
- [ ] Check keyboard use, VoiceOver, contrast, dark mode, and larger text. **Done when:** primary flows work without a mouse.

## 4. Completion

- [ ] Run the manual matrix in `requirements/05-quality-and-acceptance.md` and measure latency, buffer underruns, and CPU use. **Done when:** results and measurement conditions are recorded and quality criteria are refined.
- [ ] Update the README with build, launch, permission, and BlackHole installation instructions. **Done when:** a new developer can run the app from the instructions.
- [ ] Prepare a release build and repeat acceptance scenarios. **Done when:** a signed build is verified on a supported macOS version.
