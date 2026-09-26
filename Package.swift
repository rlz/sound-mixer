// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundMixerDomain",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SoundMixerDomain", targets: ["SoundMixerDomain"]),
               .library(name: "SoundMixerStorage", targets: ["SoundMixerStorage"])],
    targets: [
        .target(
            name: "SoundMixerDomain",
            path: "SoundMixer",
            sources: ["Domain", "Audio/RealtimePeakMeter.swift", "Audio/RealtimeAudioRingBuffer.swift"]
        ),
        .target(name: "SoundMixerStorage", dependencies: ["SoundMixerDomain"], path: "SoundMixer/Storage"),
        .testTarget(name: "SoundMixerDomainTests", dependencies: ["SoundMixerDomain"], path: "Tests/SoundMixerDomainTests"),
        .testTarget(name: "SoundMixerStorageTests", dependencies: ["SoundMixerStorage", "SoundMixerDomain"], path: "Tests/SoundMixerStorageTests"),
    ]
)
