# 01. Devices and Virtual Buses

## Physical outputs

- The left panel lists every available Core Audio device with output channels, regardless of whether it is the system output.
- Each item shows its current or last-known name (or UID if no name is known), type, availability, and a 0–100% master volume slider for its mix.
- The list updates on device connection, disconnection, and property changes without restarting the app.
- The native state snapshot contains the union of currently discovered devices and UIDs referenced by saved input, output, or BlackHole settings. Each entry distinguishes live discovery from saved roles, reports channel counts when discovered, and uses the live name or last-known name for display. A configured UID with no discovered device is reported unavailable; this state alone does not start or stop audio.
- A device is identified by its Core Audio UID. The output list combines discovered devices and output-mix UIDs from saved configuration. If a configured output disappears, including before app launch, it remains listed as “Unavailable,” with its mix and an action to remove the saved setting. Removal does not affect the Core Audio device.
- For configured input and output devices and BlackHole routes, save the last-known name for display only; show the UID if no name is known. A saved name does not imply that the device is connected. When a device with the same UID is discovered, update its name and properties, check compatibility, and resume it without recreating its mix. A different UID is a different device.
- Available outputs without a saved mix appear in the list but do not become saved ghosts after disconnection. Removing the setting for a missing output removes it from the list; an available output stays listed as a discovered device.
- An installed BlackHole device remains visible among Core Audio devices. Created BlackHole routes appear separately and refer to that device; the interface distinguishes them to avoid confusion.

## Internal virtual buses

- The user can create, rename, and delete a bus. Its name must not be empty after trimming whitespace; duplicate names are allowed because its UUID is the identifier.
- A bus has its own mix and master volume and can be a source in another mix.
- A bus does not appear in macOS Sound settings and cannot be selected as an output device by another app. The creation interface states this clearly.
- When deleting a bus, the interface shows affected routes; after confirmation, references to the bus are removed from mixes.

## BlackHole routes

- Creation requires an installed, available BlackHole device. The user selects a specific instance by UID and its output channels from the discovered list.
- A route has an editable name, its own mix, and master volume. Selected channel indices are saved within the selected device.
- For a stereo mix, the user can select two distinct channels. A mono route can use one channel. Other channel layouts require separate design after prototype verification.
- Overlapping channels in two active routes on the same device are forbidden so the mixes cannot overwrite each other.
- If a mix is configured for a BlackHole device in the physical-output row, it occupies that device's output channels; a BlackHole route with overlapping channels is forbidden. Before implementation, check whether a subset of channels can be assigned to this base mix. Until then, it reserves every output channel of the device.
- The `prototypes/channel-routing/` prototype confirmed writing to any single channel or two distinct channels of BlackHole 64ch using a full multichannel client buffer. In the first release, the base BlackHole mix still reserves all channels until subset selection is specified as a separate user action.
- If the driver is missing, channel count changes, or the device disconnects, the route is retained as unavailable and does not start. The interface offers selection of available channels or a device.
- A saved BlackHole route stays visible and removable even if the driver was missing at launch. When an instance with the same UID returns, it can start only after its selected channels and conflicts are checked again.
- Sound Mixer does not install or update BlackHole automatically.

## Sliders

- Master volume is a software gain applied to the mix result: 0% is silence and 100% is unity gain.
- Moving a slider applies its value without restarting the audio pipeline and is reflected in the interface after native confirmation.
- Device system volume remains independent of this slider when the device has a hardware volume control.
