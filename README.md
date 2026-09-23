# Sound Mixer

Sound Mixer is an audio mixer for modern macOS versions. It collects audio from input devices, individual applications, and internal virtual buses, mixes them with independent volume levels, and routes the result to physical output devices or selected BlackHole channels.

## Status

The application scaffold is ready: an AppKit window loads the local React interface through WKWebView. The audio pipeline, device support, and mix controls have not been implemented yet. The implementation order and acceptance criteria are in [todo.md](todo.md).

## How the mixer will work

- The left panel lists available Core Audio outputs, internal virtual buses, and configured BlackHole routes. Each output or bus has a master volume slider.
- Users can create and rename internal virtual buses. These buses exist only in Sound Mixer and do not appear as macOS system devices.
- For a BlackHole route, users select an installed BlackHole device and its output channels. If BlackHole is missing, the app explains how to install it and does not create a nonfunctional route.
- The right panel configures the mix for the selected output or bus using input devices, applications, and other virtual buses as sources. Each source has its own volume control. A mono source can be sent to both stereo channels.
- Invalid routes, including cycles between virtual buses, are rejected before they are applied.
- A master switch turns the mixer's entire audio pipeline on or off. Normal macOS playback continues when mixing is off and after Sound Mixer exits. Settings are saved automatically and restored on the next launch.
- If a configured device is missing at launch, its settings and mix rows remain visible with an unavailable status and can be removed. If a device with the same UID returns, valid routes resume when mixing is on.

See the detailed requirements for [product scope](requirements/00-product.md), [devices](requirements/01-devices.md), [routing and mixing](requirements/02-routing-and-mixing.md), [interface](requirements/03-interface.md), [macOS integration](requirements/04-macos-integration.md), and [quality and acceptance](requirements/05-quality-and-acceptance.md).

## Technology and project structure

- **Swift** and **Core Audio** handle device discovery, capture, the routing graph, mixing, and audio output.
- **AppKit + WKWebView** provide the macOS window and host the interface.
- **TypeScript + React + Tailwind CSS** provide the interface and view state. Audio processing and persistent configuration remain in Swift.
- **Font Awesome Free** SVG icons are bundled with the local React build, without a CDN.
- Swift and WebKit communicate through typed messages. The native side confirms settings changes, which are then reflected in the interface.
- Versioned local configuration in Application Support automatically stores routes, levels, names, selected channels, and the master switch state. It does not store source audio.

The first version targets **macOS 15 and later**. The scaffold has been verified with **Xcode 27.0 / macOS SDK 27.0**, Node.js 26.8.1, and npm 12.0.2. Core Audio process taps are planned for application audio capture; this feature depends on permission to record system audio. Users install BlackHole separately.

## Development

1. Open [SoundMixer.xcodeproj](SoundMixer.xcodeproj) in Xcode 27 or later and run the `SoundMixer` scheme on a Mac. Built interface files in `Web/dist` are committed to the repository and copied into the `.app`, so a normal clean Xcode build does not require Node.js or network access.
2. To change the interface, run `cd Web && npm ci && npm run build`, then rebuild the app in Xcode. This updates `Web/dist`; commit the built files alongside the source changes. At runtime, the app loads only local files.
3. Run all checks with `./scripts/check.sh`. It installs the pinned SwiftFormat 0.62.1 and SwiftLint 0.65.0 releases after verifying their SHA256 checksums, runs them, then runs `npm ci`, Prettier and ESLint checks, the Web build, and the Xcode build. Xcode 27 and Node.js 26.8.1 are required. If only Command Line Tools are active, the script uses `/Applications/Xcode.app`.

To fix formatting, run `.tools/bin/swiftformat SoundMixer Tests --config .swiftformat --cache ignore` and `cd Web && npm run format`. The configuration uses four spaces for Swift, TypeScript, TSX, JavaScript, JSON, HTML, and CSS; the Prettier plugin sorts Tailwind classes. Web tool versions are pinned in `Web/package.json` and `Web/package-lock.json`. GitHub Actions runs formatting, linting, Swift tests, and builds with the Xcode 27 image.

## Technical references

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [Apple: AudioHardwareSystem and device discovery](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)
- [Apple: Requesting authorization for media capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [BlackHole: official repository](https://github.com/ExistentialAudio/BlackHole)
