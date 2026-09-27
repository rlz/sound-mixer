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
            exclude: [
                "AppDelegate.swift", "BridgeState.swift", "Info.plist", "Storage", "main.swift",
                "Audio/AudioCaptureCoordinator.swift", "Audio/AudioCaptureSessions.swift",
                "Audio/AudioRoutingCoordinator.swift",
                "Audio/AudioSourceFanout.swift", "Audio/CoreAudioDeviceCatalog.swift",
                "Audio/CoreAudioOutputCoordinator.swift", "Audio/CoreAudioOutputMute.swift",
                "Audio/CoreAudioProcessCatalog.swift", "Audio/RealtimePublication.swift",
            ],
            sources: ["Domain", "Audio/AudioGraphRenderer.swift", "Audio/RealtimePeakMeter.swift", "Audio/RealtimeAudioRingBuffer.swift"]
        ),
        .target(name: "SoundMixerStorage", dependencies: ["SoundMixerDomain"], path: "SoundMixer/Storage"),
        .testTarget(name: "SoundMixerDomainTests", dependencies: ["SoundMixerDomain"], path: "Tests/SoundMixerDomainTests"),
        .testTarget(name: "SoundMixerStorageTests", dependencies: ["SoundMixerStorage", "SoundMixerDomain"], path: "Tests/SoundMixerStorageTests"),
    ]
)
