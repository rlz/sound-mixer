# 03. Interface

## Language

- English is the default interface language, including window text, error messages, and system permission descriptions.
- The HTML document declares English; the macOS app's development language is English.

## Icons

- Use free Font Awesome SVG icons in the React interface through the official `@fortawesome/react-fontawesome` component. Import only used icons from `@fortawesome/free-*-svg-icons` packages so they are included in the local build and work offline.
- Icons supplement action or state text. An icon-only button has an accessible English name; decorative icons are hidden from VoiceOver. Device unavailability and errors are not conveyed with an icon alone.

## Window

- The WebKit bridge accepts a versioned state snapshot from Swift and an allowlist of typed commands. The page sends a `ready` command after subscribing so the initial snapshot cannot be lost during startup. Every command includes a request ID and receives an accepted or rejected result. Swift validates required fields and ranges before saving; rejected commands leave saved state unchanged. State snapshots combine discovered outputs with configured output mixes, buses, and BlackHole routes. Audio graph application is added with the audio engine.
- The initial device screen is read-only. It lists only discovered devices with output channels and saved output mixes, and shows each item's name, UID, output channel count, and availability. A saved UID with no matching output remains visible as disconnected. Input-only devices are not listed as outputs.

- The main window uses a compact, information-dense professional layout with a persistent header and three aligned work areas below it. Keep names, availability, levels, and primary actions visible without requiring repeated navigation; use text and accessible control labels rather than icon-only or color-only states. The layout adapts to narrower windows while preserving access to all three areas.
- A master “Mixing On/Off” switch with clear text state appears at the top, independently of the selected item.
- The header contains the Sound Mixer name and master “Mixing On/Off” switch with a clear text state, independently of the selected item.
- The left area lists output destinations in “Output Devices,” “Virtual Buses,” and “BlackHole Routes” groups. All physical outputs appear whether or not a mix is configured, except the BlackHole driver device itself. “BlackHole Routes” contains only virtual routes created by the user; it does not list the underlying driver device as an output. Rows select an item, and selection is distinguishable without relying on color alone.
- The center area shows the selected destination's settings and mix: name and type, availability, channel count, UID or route details as appropriate, route error, output level, source rows, per-route source levels, and add-source action. Virtual item names are editable here; physical device names are read-only. Keep source rows compact and scannable.
- The right area lists every discovered physical input device, saved input devices that are currently disconnected, and every application source the user has added. Input devices show availability and a live signal-level meter while capture is active. Added applications show availability and a live signal-level meter while running. A previously added application that is not running remains in the list as unavailable and resumes automatically when a matching process is available again. Do not populate this area with every running application by default: provide an add-application action that opens a separate searchable catalog of eligible applications.
- Each input device and added application has a mute control in the right area. Muting a source prevents it from contributing to every route, without deleting its mix rows or changing their per-route levels. Mute state is saved and restored. Unmuting makes the source eligible to contribute again when it is available and permitted.
- Selecting an output opens its settings in the center area. Selecting a virtual bus or BlackHole route opens its settings there; its saved name is edited there and persisted after native confirmation. Muting does not stop capture, so an actively captured muted source can continue to show its input level.
- Configured outputs, buses, and BlackHole routes show their source rows with per-source levels and removal controls. Input sources also expose mono placement. New rows can be added from available physical inputs, applications with active output, and buses; missing saved sources remain visible and removable. Destination and mix master-level editing remains a separate control.
- A saved but missing output stays in the Output Devices group after restart. Its mix remains saved and is shown inactive while that UID is disconnected; it automatically becomes active again when that same device returns. The user can select it, inspect its mix, and explicitly remove the saved mix. Before removal, show that this mix's rows will be deleted; the macOS device itself is not removed. Device absence never deletes a mix automatically.
- An add button creates an internal bus or BlackHole route. A virtual item's name can be edited inline or in its settings.
- Bus creation and renaming use an in-interface form so name entry works consistently in WKWebView.
- Deleting a virtual bus that is still used as a source by another mix is rejected with a validation error; remove those source rows first. Bus names are trimmed, must be non-empty, and are limited to 64 characters.
- The add-source catalog separates input devices, applications, and internal buses. Applications are added explicitly from the searchable application catalog; the catalog lists eligible currently running applications and does not add them merely by browsing. Buses remain available as mix sources in the center area.
- When adding a source, unavailable items include a reason. The catalog does not offer a new row for a missing input device.
- An existing input stays in its mix row when its device is missing, including at launch. It is shown unavailable and can be explicitly removed from the mix. The interface does not offer to create a new row for a missing device, and device absence never removes a source row automatically.
- A mono source offers “Left,” “Right,” and “Stereo” placement; a stereo source does not show this choice.

## States and feedback

- An empty mix explains how to add a source.
- Microphone or system-audio permission denial appears beside the affected source and provides an action to open System Settings.
- Missing BlackHole and lack of free channels are explained before route creation.
- A saved BlackHole route remains visible and removable when the driver or selected instance is missing. For missing devices, show the last-known name if saved and the UID in details; otherwise use the UID as the name. Status text explicitly says the device is disconnected.
- A route validation error identifies affected items and does not change the active audio graph.
- Level and name changes appear after successful confirmation from Swift. On failure, the UI restores the confirmed value and shows the reason.
- While mixing is off, sliders and mix contents remain visible and editable; the interface states that Sound Mixer is not currently outputting audio.
- Swift state snapshots combine saved items and discovered devices, reporting availability and each route's stop reason separately. After a missing device is connected or removed, the interface updates from a confirmed snapshot without restarting the window.

## Accessibility

- All actions are keyboard accessible; sliders have text labels and numeric values.
- Respect the macOS system text size, contrast, and dark mode.
- Convey device state and errors in text, not only with an icon or color.
