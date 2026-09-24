# Development Plan

Statuses: `[ ]` = not started, `[~]` = in progress. Tasks are ordered by dependency; design decisions and acceptance details live in `requirements/`.

## 1. Domain model and configuration

- [~] Add per-mix physical-input routing and gain in configuration schema v4. **Done when:** each physical-input mix row stores routing and gain per hardware channel; routing defaults to mono → both, channel 1 → first, channel 2 → second, remaining channels → ignore; gains default linked at unity; independent levels and link state serialize and validate per mix. Domain defaults, validation, initialization on add, typed bridge updates, and an accessible channel routing/gain editor are in place. Linked gains preserve channel ratios; per-channel meters and realtime application of settings remain.
- [~] Add BlackHole stereo-pair routes as mix sources. **Done when:** route UUIDs are valid source references, route dependencies participate in bus/route cycle validation, and confirmed route deletion atomically removes every source and mute reference; cancellation or save failure preserves the configuration. Domain references, cross-node cycle validation, bridge encoding, and transactional cascade deletion are implemented. Route-pair input capture and end-to-end source selection/rendering remain.

## 2. Native audio pipeline

- [~] Finish physical output and BlackHole route output. **Done when:** physical outputs work, each BlackHole route receives the lowest available adjacent stereo pair (1/2, 3/4, 5/6, …), and conflicts or exhausted pairs are reported without changing active routing. Format conversion quality and device-level routing remain to verify.
- [ ] Capture, meter, and route multichannel physical inputs. **Done when:** supported 1–64 channel HAL inputs are captured in their actual format, each channel has a transient pre-gain meter, and every mix row applies its per-channel gain and Ignore/First/Second/Both routing without allocation or blocking in audio callbacks.
- [ ] Capture configured BlackHole routes as stereo inputs. **Done when:** each route captures its same assigned pair from the device input side; input-side channel availability, capture state, and meters are reported per pair.
- [~] Handle device disconnection, reconnection, and format changes. **Done when:** the same UID resumes valid routes after compatibility checks, other routes continue independently, and mixing Off never starts capture or output. Same-device reconnect and changed-format checks remain.
- [~] Finish master-switch and app-exit lifecycle checks. **Done when:** Off, exit, and relaunch release resources and resume only when the saved state and current devices allow it. Native stop behavior is implemented; Mac verification remains.
- [~] Finish startup restoration and unavailable-route reporting. **Done when:** saved Off stays off, saved On starts available routes, and unavailable routes remain editable with a specific reason. Startup restoration is connected; user-visible verification remains.

## 3. Bridge and interface

- [~] Finish typed bridge validation and state synchronization. **Done when:** new channel-routing and BlackHole-source commands validate types and ranges, persist atomically, and rejected edits leave the active graph unchanged. Existing mix edit commands are connected; end-to-end rejection checks remain.
- [~] Finish BlackHole route management. **Done when:** route creation selects only a BlackHole device, allocates the next adjacent stereo pair automatically, names it `BlackHole {first}/{second}`, and allows renaming. Remove the mono and channel-selection controls. Deleting a used route warns that its source rows will be removed throughout the configuration, then removes all references atomically on confirmation.
- [ ] Show configured BlackHole pairs under Inputs. **Done when:** each output route appears as the same named stereo input pair with availability, capture state, meter, mute, and Add to mix controls; the row updates after route rename/deletion and device changes.
- [ ] Add per-channel meters and controls to physical-input mix rows. **Done when:** a Channels button opens a compact accessible editor showing every discovered channel's live meter, routing choice, and gain; gains are linked by default, unlinking exposes individual sliders, and re-linking copies channel 1's gain to all channels. Settings are saved per mix row and restored after destination changes and relaunch.
- [~] Finish source panels and mix editing. **Done when:** inputs, applications, buses, outputs, and mixes show clear state, levels, and accessible controls; sources can be added or removed, and missing saved sources remain manageable. Core add/remove and level flows exist; remaining catalog, meter, and unavailable-state work is tracked below and in requirements.
- [~] Finish live meters and source states. **Done when:** capture, per-mix source, and destination meters reflect the specified signal points, expire when stale, update at no more than 15 Hz, and remain realtime-safe. Meter pipeline and UI are implemented; Mac signal, permission, staleness, and accessibility checks remain.
- [~] Finish permission and unavailable-device feedback. **Done when:** denied permissions, missing devices, missing BlackHole, and route errors have clear text and recovery actions without blocking independent routes. Main states are displayed; signed-app and Mac checks remain.
- [~] Finish dense, consistent three-panel layout. **Done when:** input, output, and mix panels remain scannable at minimum window width with accessible names and essential state visible without relying on icon or color. Layout spacing is reduced; minimum-width review remains.
- [ ] Verify keyboard, VoiceOver, contrast, dark mode, and larger text. **Done when:** primary flows remain usable and understandable in each mode.

## 4. Acceptance and release

- [ ] Run the manual matrix in `requirements/05-quality-and-acceptance.md`, including Scarlett per-channel meters/gains and BlackHole pair loopback; measure latency, underruns, and CPU. **Done when:** observations cover linked defaults, independent gain changes, relinking to channel 1, device details, and measurement conditions.
- [ ] Update the README with build, launch, permission, and BlackHole installation instructions. **Done when:** a new developer can run the app from the instructions.
- [ ] Prepare a release build and repeat acceptance scenarios. **Done when:** a signed build is verified on a supported macOS version.
