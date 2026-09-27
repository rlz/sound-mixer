# 01. Devices and Virtual Buses

## Physical outputs

- The left panel lists every available Core Audio device with output channels, regardless of whether it is the system output.
- Each item shows its current or last-known name (or UID if no name is known), type, availability, and live device volume where Core Audio exposes a writable main control. The volume slider remains available without a saved mix; disconnected or unsupported devices show why it cannot be changed.
- The list updates on device connection, disconnection, and property changes without restarting the app.
- Device settings are opened from the top toolbar. The dialog lists discovered physical devices and lets the user disable or enable each by Core Audio UID. Devices are active by default, including newly discovered or otherwise unrecognized devices. Disabling a device immediately stops Rlz Sound Mixer capture, output, and metering for that UID and removes it from the main input and output panels. Its saved routes remain available for restoration when enabled again; disabling does not change Core Audio device settings. The existing `hiddenDeviceUIDs` configuration field stores disabled UIDs and keeps them inactive across app launches and device reconnection.
- The native state snapshot contains the union of currently discovered devices and UIDs referenced by saved input or output settings. Each entry distinguishes live discovery from saved roles, reports channel counts when discovered, and uses the live name or last-known name for display. A configured UID with no discovered device is reported unavailable; this state alone does not start or stop audio.
- A device is identified by its Core Audio UID. The output list combines discovered devices and output-mix UIDs from saved configuration. If a configured output disappears, including before app launch, it remains listed as “Unavailable,” with its mix and an action to remove the saved setting. Removal does not affect the Core Audio device.
- For configured input and output devices, save the last-known name for display only; show the UID if no name is known. A saved name does not imply that the device is connected. When a device with the same UID is discovered, update its name and properties, check compatibility, and resume it without recreating its mix. A different UID is a different device.
- Available outputs without a saved mix appear in the list but do not become saved ghosts after disconnection. Removing the setting for a missing output removes it from the list; an available output stays listed as a discovered device.
- Physical-device identity remains its Core Audio UID; internal buses use their own UUIDs.

## Internal virtual buses

- Create virtual buses from the Device settings dialog. The dialog stays open and the current destination selection does not change after creation. The dialog also shows existing buses; creating one does not make it a macOS system device.
- A virtual bus can be deleted from its card or Device settings. Deletion is rejected while another mix references the bus; remove those source rows first.
- The user can create, rename, and delete a bus. Creation assigns the first unused sequential name in the form `Virtual Bus 1`, `Virtual Bus 2`, and so on; the user can rename it later. Custom names must not be empty after trimming whitespace and are limited to 64 characters. Duplicate custom names are allowed because the UUID is the identifier.
- A bus has its own mix and saved software Mix gain and can be a source in another mix.
- A bus does not appear in macOS Sound settings and cannot be selected as an output device by another app. The creation interface states this clearly.
- When deleting a bus, the interface shows affected routes; after confirmation, references to the bus are removed from mixes.

## Sliders

- Physical output sliders read and set writable device main volume; they are available without a saved mix. An output without a writable main volume shows the limitation. Internal virtual buses use saved software Mix gain: 0% is silence and 100% is unity gain.
- Moving a slider applies its value without restarting the audio pipeline and is reflected in the interface after native confirmation.
- Physical output device volume and mute are not stored in the mix configuration. A separate mute control preserves the current volume; devices without a writable mute property show it as unavailable. Rlz Sound Mixer restores earlier values on normal exit when they still match the last app-set values.
- Previously saved physical-output mix gains are set to unity at startup, and physical-output rendering stays at unity. Changing a physical device's volume does not modify an application's global App gain or a virtual destination's Mix gain.
