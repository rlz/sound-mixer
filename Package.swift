// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundMixerDomain",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SoundMixerDomain", targets: ["SoundMixerDomain"])],
    targets: [
        .target(name: "SoundMixerDomain", path: "SoundMixer/Domain"),
        .testTarget(name: "SoundMixerDomainTests", dependencies: ["SoundMixerDomain"], path: "Tests/SoundMixerDomainTests"),
    ]
)
