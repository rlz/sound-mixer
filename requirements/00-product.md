# 00. Product Scope

## Goal

A user manages several independent audio mixes on a Mac: selects sources, sets levels, and sends the result to physical outputs, internal virtual buses, or BlackHole channels.

## Terms

- **Physical output** — a Core Audio device available to the system with output channels, such as speakers, headphones, a USB interface, or an installed virtual driver.
- **Internal virtual bus** — a user-created mixing graph node that exists only in Sound Mixer.
- **BlackHole route** — a user-created mixer output tied to a specific installed BlackHole device and selected output channels.
- **Source** — an audio input device, audio from a particular application, or an internal virtual bus added to a mix.
- **Master volume** — a software gain for the selected output or bus mix. It does not change the device's system volume.
- **Master switch** — the on/off state of Sound Mixer's entire audio pipeline. It persists across launches.

## User scenarios

1. The user sees all available output devices and selects one to configure its mix.
2. The user adds a microphone and application audio to a headphone mix, setting an independent volume for each source.
3. The user creates a bus named “Stream,” renames it, and adds it as a source to several output mixes.
4. The user creates a BlackHole route, selects one channel or a stereo pair, and sends a separate mix there.
5. The user disconnects a device or revokes a permission; the app preserves the configuration and clearly shows which sources are unavailable.
6. The user turns off mixing in one action; normal macOS audio continues playing. Audio also behaves normally after the app exits.
7. The user relaunches Sound Mixer and gets the saved names, routes, levels, channels, and master switch state.
8. The user starts Sound Mixer without a previously configured device. The saved output, input, or BlackHole route appears as unavailable and can be removed. When a device with the same UID returns, valid routes resume automatically if mixing is on.

## First release

- One local user and one local configuration.
- Interactive control of mixes in real time, automatic saving of every accepted change, and restoration of settings across launches.
- Manual addition of sources to each mix. The same bus or source may participate in multiple valid mixes.
- No file recording, network broadcasting, audio effect plugins, or custom system audio driver.

## Decisions requiring prototype verification

- How to capture audio from individual applications, which processes are available, and precisely how their audio behaves when routed through process taps.
- How multiple outputs with different clocks work: choose sample-rate conversion and synchronization after measurement.
- Device-specific format and channel-independence limits; the interface must show channels that are actually available.

These are technical checks early in development, not promises of specific system behavior before verification on a supported macOS version.
