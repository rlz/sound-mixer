# 03. Interface

## Language

- English is the default interface language, including window text, error messages, and system permission descriptions.
- The HTML document declares English; the macOS app's development language is English.

## Icons

- Use free Font Awesome SVG icons in the React interface through the official `@fortawesome/react-fontawesome` component. Import only used icons from `@fortawesome/free-*-svg-icons` packages so they are included in the local build and work offline.
- Icons supplement action or state text. An icon-only button has an accessible English name; decorative icons are hidden from VoiceOver. Device unavailability and errors are not conveyed with an icon alone.

## Window

- The main window has two panels: output devices and virtual buses on the left, and the selected item's mix settings on the right.
- A master “Mixing On/Off” switch with clear text state appears at the top, independently of the selected item.
- The left panel has “Output Devices,” “Virtual Buses,” and “BlackHole Routes” groups. All physical outputs appear whether or not a mix is configured.
- Each row on the left has a name, availability indicator, and master volume slider. Selection is distinguishable without relying on color alone.
- A saved but missing output stays in the Output Devices group after restart. The user can select it, inspect its mix, and remove the saved setting. Before removal, show that this mix's rows will be deleted; the macOS device itself is not removed.
- An add button creates an internal bus or BlackHole route. A virtual item's name can be edited inline or in its settings.
- The right panel shows the selected item's name and type, mix source list, each source's slider, and an add-source action.
- When adding a source, the catalog separates input devices, applications, and internal buses. Unavailable items include a reason.
- An existing input stays in its mix row when its device is missing, including at launch. It can be removed from the mix. The interface does not offer to create a new row for a missing device.
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
