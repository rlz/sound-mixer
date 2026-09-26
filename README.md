# Sound Mixer

Sound Mixer is an audio mixer for modern macOS versions. It collects audio from input devices, individual applications, and internal virtual buses, mixes them with independent volume levels, and routes the result to physical output devices or selected BlackHole channels.

## Status

The application has a native Core Audio capture and output pipeline, configurable mixes, per-mix channel matrices and input gain settings, multichannel physical outputs, BlackHole stereo-pair output routes, automatic local configuration storage, and a React interface hosted in WKWebView. Some parts of the multichannel physical-input path and BlackHole pair input capture are still in progress; see [todo.md](todo.md) for implementation and verification status.

## Current behavior and limitations

- The left panel lists available Core Audio outputs, internal virtual buses, and configured BlackHole routes. Physical outputs expose device volume when Core Audio provides a writable main control; buses and BlackHole routes use software Mix gain.
- Users can create and rename internal virtual buses. These buses exist only in Sound Mixer and do not appear as macOS system devices.
- BlackHole routes use the lowest available adjacent stereo output pair automatically. The installed driver remains a separate dependency and is never installed by Sound Mixer.
- Sound Mixer classifies items as `system` (Core Audio devices excluding BlackHole), `virtual` (internal buses), and `blackhole` (created BlackHole stereo pairs). Installed BlackHole devices appear as physical Inputs/Outputs and in the route-creation selector; configured channel pairs appear as separate route inputs and destinations.
- Mix sources include physical inputs, eligible applications, virtual buses, and configured BlackHole routes. Every mix source has a channel matrix per destination; a six-channel physical output exposes six destination channels, and one source channel can feed several of them. Physical input rows also store per-channel gains. Physical capture accepts 1–64 channels and exposes per-channel meters; multichannel device behavior still needs live Mac verification.
- The master switch controls Sound Mixer's capture and output. Configuration is saved locally and restored at launch. Missing devices remain visible with an unavailable state.
- Sound Mixer does not change the macOS default output device. Device volume changes made in Sound Mixer are restored on normal exit if the device still has the app-set value. Devices without a writable main volume cannot be adjusted here. Application capture and physical-output metering depend on macOS System Audio Recording permission.

See the detailed requirements for [product scope](requirements/00-product.md), [devices](requirements/01-devices.md), [routing and mixing](requirements/02-routing-and-mixing.md), [interface](requirements/03-interface.md), [macOS integration](requirements/04-macos-integration.md), and [quality and acceptance](requirements/05-quality-and-acceptance.md).

## Technology and project structure

- **Swift** and **Core Audio** handle device discovery, capture, the routing graph, mixing, and audio output.
- **AppKit + WKWebView** provide the macOS window and host the interface.
- **TypeScript + React + Tailwind CSS** provide the interface and view state. Audio processing and persistent configuration remain in Swift.
- **Font Awesome Free** SVG icons are bundled with the local React build, without a CDN.
- Swift and WebKit communicate through typed messages. The native side confirms settings changes, which are then reflected in the interface.
- Versioned local configuration in Application Support automatically stores routes, levels, names, selected channels, and the master switch state. It does not store source audio.

The first version targets **macOS 15 and later**. The project is configured for **Xcode 27.0 / macOS SDK 27.0**, Node.js 26.8.1, and npm 12.0.2. Application audio capture uses Core Audio process taps and requires System Audio Recording permission. Users install BlackHole separately.

## Build and launch

Requirements: macOS 15 or later, Xcode 27 or later, Node.js 26.8.1, and npm 12.0.2. From the repository root:

```sh
./scripts/build-all.sh
open SoundMixer.xcodeproj
```

In Xcode, select the **SoundMixer** scheme and run it on **My Mac**. The build script builds the local React interface, then builds the macOS app; the web assets are bundled into the app, so runtime does not require a network connection. To build without opening Xcode, run `./scripts/build-core.sh` after building the web assets, or use `./scripts/build-all.sh` for both steps.

The first time you add a physical input, macOS may ask for Microphone access. Turning Mixing on starts physical-output meters and may ask for System Audio Recording access even before you add an application source. Grant access in **System Settings → Privacy & Security** for the relevant Sound Mixer permission, then turn the mixer off and on or restart capture. If access is denied, macOS may require quitting and reopening the app after changing the setting. A denied output meter is shown as inactive; it does not stop independent routes.

To run the repository's formatting, lint, test, web-build, and app-build checks, use `./scripts/check.sh`. It installs the pinned SwiftFormat and SwiftLint binaries after checksum verification and uses the locked npm dependencies. Xcode 27 and Node.js 26.8.1 are required.

## Install BlackHole

Sound Mixer does not bundle or install the BlackHole audio driver. Install a BlackHole build from the [official BlackHole repository](https://github.com/ExistentialAudio/BlackHole#installation-instructions), follow its installer instructions, and approve the system extension or restart if the installer requests it. Then open **Audio MIDI Setup** or Sound Mixer's device list and confirm the BlackHole device is available. In Sound Mixer, add a BlackHole route and choose the discovered BlackHole device; Sound Mixer assigns the next available stereo pair. A route can be unavailable if the driver is absent, disconnected, or does not expose its saved channels.

BlackHole routes are intended for audio routing and loopback. Configure the application or macOS audio path to send audio into the corresponding BlackHole input when loopback is desired. Sound Mixer meters device-directed audio from other applications but does not route that audio into a mix automatically.

## Development

Web source lives in `Web/src`; `Web/dist` is generated by the build and ignored by Git. Do not commit its contents. Use `npm run build` from `Web` while iterating on the interface. Swift and web tool versions and formatting rules are pinned in the repository. To fix formatting, run `.tools/bin/swiftformat SoundMixer Tests --config .swiftformat --cache ignore` and `cd Web && npm run format`.

## Technical references

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [Apple: AudioHardwareSystem and device discovery](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)
- [Apple: Requesting authorization for media capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [BlackHole: official repository](https://github.com/ExistentialAudio/BlackHole)
