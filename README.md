# Rlz Sound Mixer

Rlz Sound Mixer is an audio mixer for modern macOS versions. It collects audio from input devices, individual applications, and internal virtual buses, mixes them with independent volume levels, and routes the result to physical output devices.

## Status

The application has a native Core Audio capture and output pipeline, configurable mixes, per-mix channel matrices and input gain settings, multichannel physical outputs, automatic local configuration storage, and a React interface hosted in WKWebView. Some parts of the multichannel physical-input path are still in progress; see [todo.md](todo.md) for implementation and verification status.

## Current behavior and limitations

- The left panel lists available Core Audio outputs and internal virtual buses. Physical outputs expose device volume where Core Audio provides a writable main control; buses use software Mix gain.
- Users can create and rename internal virtual buses. These buses exist only in Rlz Sound Mixer and do not appear as macOS system devices.
- Mix sources include physical inputs, eligible applications, and virtual buses. Every mix source has a channel matrix per destination; a six-channel physical output exposes six destination channels, and one source channel can feed several of them. Physical input rows also store per-channel gains. Physical capture accepts 1–64 channels and exposes per-channel meters; multichannel device behavior still needs live Mac verification.
- The master switch controls Rlz Sound Mixer's capture and output. Configuration is saved locally and restored at launch. Missing devices remain visible with an unavailable state.
- Rlz Sound Mixer does not change the macOS default output device. Device volume changes made in Rlz Sound Mixer are restored on normal exit if the device still has the app-set value. Devices without a writable main volume cannot be adjusted here. Application capture and physical-output metering depend on macOS System Audio Recording permission.

See the detailed requirements for [product scope](requirements/00-product.md), [devices](requirements/01-devices.md), [routing and mixing](requirements/02-routing-and-mixing.md), [interface](requirements/03-interface.md), [macOS integration](requirements/04-macos-integration.md), and [quality and acceptance](requirements/05-quality-and-acceptance.md).

## Technology and project structure

- **Swift** and **Core Audio** handle device discovery, capture, the routing graph, mixing, and audio output.
- **AppKit + WKWebView** provide the macOS window and host the interface.
- **TypeScript + React + Tailwind CSS** provide the interface and view state. Audio processing and persistent configuration remain in Swift.
- **Font Awesome Free** SVG icons are bundled with the local React build, without a CDN.
- Swift and WebKit communicate through typed messages. The native side confirms settings changes, which are then reflected in the interface.
- Versioned local configuration in Application Support automatically stores routes, levels, names, selected channels, and the master switch state. It does not store source audio.

The first version targets **macOS 15 and later**. The project is configured for **Xcode 27.0 / macOS SDK 27.0**, Node.js 26.8.1, and npm 12.0.2. Application audio capture uses Core Audio process taps and requires System Audio Recording permission.

## Build and launch

Requirements: macOS 15 or later, Xcode 27 or later, Node.js 26.8.1, and npm 12.0.2. From the repository root:

```sh
./scripts/build-all.sh
open SoundMixer.xcodeproj
```

In Xcode, select the **SoundMixer** scheme and run it on **My Mac**. The build script builds the local React interface, then builds the macOS app; the web assets are bundled into the app, so runtime does not require a network connection. To build without opening Xcode, run `./scripts/build-core.sh` after building the web assets, or use `./scripts/build-all.sh` for both steps. These scripts use the same Xcode DerivedData location as the IDE.

The first time you add a physical input, macOS may ask for Microphone access. Turning Mixing on starts physical-output meters and may ask for System Audio Recording access even before you add an application source. Grant access in **System Settings → Privacy & Security** for the relevant Rlz Sound Mixer permission, then turn the mixer off and on or restart capture. If access is denied, macOS may require quitting and reopening the app after changing the setting. A denied output meter is shown as inactive; it does not stop independent routes.

Run `./scripts/format-web.sh`, `./scripts/format-core.sh`, or `./scripts/format-all.sh` to format sources. The corresponding `lint-*`, `test-*`, and `build-*` scripts run web, core, or combined checks. `test-web` currently uses Node's test runner and succeeds with zero tests while the web test suite is being established. `./scripts/check.sh` remains the full CI check, including format checks, lint, tests, and a Debug app build.

Run `./scripts/build-dmg.sh` from a clean working tree to test core and web, build Release, create a `v<MARKETING_VERSION>` Git tag, then build `dist/RlzSoundMixer-<version>.dmg` from that tag. To rebuild an existing version from its tagged source, pass the version explicitly, for example `./scripts/build-dmg.sh 0.9.0`; an existing DMG is never overwritten. The image contains `Rlz Sound Mixer.app` and an Applications shortcut, with an illustrated Finder background. This unsigned development DMG requires a Mac with Xcode 27, Node.js 26.8.1, npm 12.0.2, and `hdiutil`; it is not yet notarized for public distribution.

## Development

Web source lives in `Web/src`; `Web/dist` is generated by the build and ignored by Git. Do not commit its contents. Use `npm run build` from `Web` while iterating on the interface. Swift and web tool versions and formatting rules are pinned in the repository. To fix formatting, run `.tools/bin/swiftformat SoundMixer Tests --config .swiftformat --cache ignore` and `cd Web && npm run format`.

### Debug the web interface

Run `./scripts/debug-interface.sh` from the repository root. It builds a development React bundle with source maps, packages it into the Debug macOS app, and opens the app. Quit any running Rlz Sound Mixer instance before rebuilding native Swift code; after a web-only rebuild, reload the page from Web Inspector.

In Safari, open **Develop → Inspect Apps and Devices → Rlz Sound Mixer → Rlz Sound Mixer**. The **Console** shows JavaScript errors, **Sources** maps bundle code to `Web/src` TSX files, and **Network** shows local asset loads. Use the Inspector reload button after changing the web bundle. The Debug app opts its `WKWebView` into inspection; Release does not. If Rlz Sound Mixer is absent from Safari, launch the freshly built app and make sure Safari's Develop menu is enabled. `./scripts/build-web.sh` alone updates `Web/dist`; `./scripts/build-core.sh` packages that directory into the app.

## Technical references

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [Apple: AudioHardwareSystem and device discovery](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)
- [Apple: Requesting authorization for media capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
