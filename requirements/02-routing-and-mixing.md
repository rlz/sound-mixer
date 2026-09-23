# 02. Routing and Mixing

## Mix contents

- After selecting an item on the left, the user sees its mix on the right and can add sources from available input devices, applications with available audio output, and internal virtual buses.
- Each source in a mix has its own 0–100% level, a removal action, and an availability state. A source has at most one row in a given mix.
- Sources can participate in several mixes at once. Where possible, the engine shares capture of the same source to avoid inconsistent copies.
- An unavailable source remains in its route but contributes no audio and is marked in the interface.
- A saved input source stays visible as a mix row and can be removed even if its device was missing at launch. The same UID resumes capture after format and permission checks when it returns.

## Channels and levels

- The first release uses stereo as its internal base mix layout. For a mono input, the user can select left, right, or both output channels.
- Mono inputs default to duplication into left and right channels without changing the level of either channel. The selected placement is saved for that mix row.
- Stereo sources retain left and right channels. Sources with more channels require an explicit channel map; without one, the source is marked unsupported rather than mixed implicitly.
- The sum of sources can exceed 0 dBFS. Before output, the engine protects the result from numeric overflow and audible clipping; the specific algorithm is selected and verified with audio tests.
- Level changes must not click: the engine smooths the transition from the old gain to the new gain.

## Configuration schema

- The root contains `schemaVersion: 2`, `isEnabled`, and the `outputMixes`, `buses`, `blackHoleRoutes`, and `knownDevices` arrays. A new configuration starts with the audio pipeline off and empty mixes. During development, older schema versions are rejected rather than migrated.
- An output mix refers to a device by Core Audio UID. Buses and BlackHole routes have their own UUIDs; names are for display only and may be duplicated.
- A BlackHole route stores a device UID and `channels` with either `mode: mono` and one channel number, or `mode: stereo` and an ordered pair of left and right channel numbers. User-facing channel numbers start at 1. A bus stores no device UID and does not become a system output.
- Each mix stores a master `level` and `inputs` rows. A row stores a source reference, `level`, and `monoPlacement` (`left`, `right`, `both`). Levels are numbers from 0 to 1; range checks belong to configuration validation.
- A source reference has `kind` and `id`: `inputDevice` with a Core Audio UID, `application` with an application bundle identifier, or `bus` with a bus UUID. Process IDs are not persisted: at launch, the app matches bundle identifiers to available processes again. Applications without stable bundle identifiers cannot be saved as sources in the first release.
- Current device and application names, availability, permissions, sample rates, and channel counts belong to observed state. When a device or application disappears, its reference remains in the file. The `knownDevices` array has a `uid` and optional `lastKnownName` for each UID referenced by output mixes, inputs, and BlackHole routes. Entries are unique by UID; the name does not identify the device or establish availability. When a referenced device is discovered, its latest nonempty name replaces the saved name. Until a name is known, the interface shows the UID. Unreferenced discovered devices do not acquire saved metadata.
- Decoding rejects unknown source kinds, invalid bus UUIDs, and channel counts that do not match the route mode. A separate semantic validation step checks references, cycles, ranges, and channel conflicts before applying configuration.
- When reading the file, a missing device is not a structural or graph error and does not remove its reference. Missing devices are handled in a separate step that matches saved UIDs to discovered devices. Name metadata is removed with the last reference to its UID.

## Route graph

- Internal buses form a directed graph. A bus cannot reference itself or participate in a cycle through other buses.
- Prevent feedback from Sound Mixer's output into capture of the same application. Verify process-tap behavior with a prototype before adding applications to the source catalog.
- Before changing active configuration, validate graph structure and static channel constraints; assess current device availability separately when starting each pipeline. A failed change does not break an active mix, and a missing device does not prevent editing or deleting a saved route.
- A BlackHole device cannot simultaneously run its base physical-output-row mix and a route that uses any channel reserved by that mix.
- After a device switch, format change, or source loss, audio resumes when conditions recover without manual recreation of the mix.
- After launch and every Core Audio device-list change, match saved UIDs to discovered devices. While a device is missing, dependent capture or output is stopped and other valid routes keep working. When the same UID returns, rebuild only affected pipelines after checking format, channels, conflicts, and permissions; if that fails, show the specific reason and keep the setting.

## Audio requirements

- Audio callbacks run without blocking operations or allocation.
- Record actual sample rate, channel count, and format for each device and source. Convert incompatible streams to a common format before summing.
- Measure latency and CPU use with a reference configuration; set acceptable values after the technical prototype.

## Master switch and lifecycle

- The switch controls all outputs and virtual buses at once. In the Off state, Sound Mixer stops its capture, mixing, and output; settings remain editable.
- When switched back on, the native side checks the saved graph, devices, and permissions, then starts available routes. Unavailable routes remain in configuration with an error state.
- Connecting a device does not turn on the master switch. When it is off, the item becomes configurable but capture and output do not start.
- On app exit, its audio pipeline stops and its taps and aggregate devices are released. Other applications must continue normal playback through the system output.
- Sound Mixer does not change the system output device or hardware volume. If a user independently routes system audio into BlackHole, macOS and BlackHole settings determine that route's behavior after Sound Mixer exits.
