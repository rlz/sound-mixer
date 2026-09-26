# 01. Devices and Virtual Buses

## Physical outputs

- The left panel lists every available Core Audio device with output channels, regardless of whether it is the system output.
- Each item shows its current or last-known name (or UID if no name is known), type, availability, and live device volume where Core Audio exposes a writable main control. The volume slider remains available without a saved mix; disconnected or unsupported devices show why it cannot be changed.
- The list updates on device connection, disconnection, and property changes without restarting the app.
- The native state snapshot contains the union of currently discovered devices and UIDs referenced by saved input, output, or BlackHole settings. Each entry distinguishes live discovery from saved roles, reports channel counts when discovered, and uses the live name or last-known name for display. A configured UID with no discovered device is reported unavailable; this state alone does not start or stop audio.
- A device is identified by its Core Audio UID. The output list combines discovered devices and output-mix UIDs from saved configuration. If a configured output disappears, including before app launch, it remains listed as “Unavailable,” with its mix and an action to remove the saved setting. Removal does not affect the Core Audio device.
- For configured input and output devices and BlackHole routes, save the last-known name for display only; show the UID if no name is known. A saved name does not imply that the device is connected. When a device with the same UID is discovered, update its name and properties, check compatibility, and resume it without recreating its mix. A different UID is a different device.
- Available outputs without a saved mix appear in the list but do not become saved ghosts after disconnection. Removing the setting for a missing output removes it from the list; an available output stays listed as a discovered device.
- Device categories are `system` (Core Audio devices other than BlackHole), `virtual` (Sound Mixer internal buses), and `blackhole` (configured BlackHole stereo-pair routes). Physical-device identity remains its Core Audio UID; buses and routes use their own UUIDs.
- BlackHole driver devices are hidden as standalone items in Inputs and Outputs. They are available only in the BlackHole route-creation selector. After a route is created, its assigned stereo pair appears as a `blackhole` input and destination; deleting the route removes that pair from the interface.

## Internal virtual buses

- The user can create, rename, and delete a bus. Its name must not be empty after trimming whitespace; duplicate names are allowed because its UUID is the identifier.
- A bus has its own mix and saved software Mix gain and can be a source in another mix.
- A bus does not appear in macOS Sound settings and cannot be selected as an output device by another app. The creation interface states this clearly.
- When deleting a bus, the interface shows affected routes; after confirmation, references to the bus are removed from mixes.

## BlackHole routes

- Creation requires an installed, available BlackHole device. The user selects a specific instance by UID; Sound Mixer automatically assigns the lowest available adjacent stereo pair (1/2, 3/4, 5/6, and so on).
- A route has an editable name, its own mix, and saved software Mix gain. It always uses a stereo pair.
- Route creation does not ask for a name or channel numbers. Assign the lowest free adjacent pair in order (1/2, 3/4, 5/6, …) and generate the initial name as `BlackHole {first}/{second}`. The user can rename it after creation.
- Overlapping channels in two active routes on the same device are forbidden so the mixes cannot overwrite each other.
- If a mix is configured for a BlackHole device in the physical-output row, it occupies that device's output channels and prevents creating routes on that device. Otherwise each route reserves its automatically assigned stereo pair; overlapping reservations are forbidden.
- The `prototypes/channel-routing/` prototype confirmed writing to any single channel or two distinct channels of BlackHole 64ch using a full multichannel client buffer. Product routes use sequential stereo pairs only. The base physical-output row continues to reserve every output channel of its device.
- If the driver is missing, channel count changes, or the device disconnects, the route is retained as unavailable and does not start. The interface reports the unavailable pair; users cannot change its channels.
- A saved BlackHole route stays visible and removable even if the driver was missing at launch. When an instance with the same UID returns, it can start only after its assigned pair and conflicts are checked again.
- Sound Mixer does not install or update BlackHole automatically.

## Sliders

- Physical output sliders read and set writable device main volume; they are available without a saved mix. An output without a writable main volume shows the limitation. Internal virtual buses and BlackHole routes use saved software Mix gain: 0% is silence and 100% is unity gain.
- Moving a slider applies its value without restarting the audio pipeline and is reflected in the interface after native confirmation.
- Physical output device volume and mute are not stored in the mix configuration. A separate mute control preserves the current volume; devices without a writable mute property show it as unavailable. Sound Mixer restores earlier values on normal exit when they still match the last app-set values.
- Previously saved physical-output mix gains are set to unity at startup, and physical-output rendering stays at unity. Changing a physical device's volume does not modify an application's row gain or a virtual destination's Mix gain.
