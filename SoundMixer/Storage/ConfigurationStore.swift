import Foundation
#if SWIFT_PACKAGE
    import SoundMixerDomain
#endif

/// Owns the accepted configuration and publishes an edit only after its file is replaced.
public final class ConfigurationStore {
    public private(set) var configuration: MixerConfiguration
    public let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let restored = try JSONDecoder().decode(MixerConfiguration.self, from: data)
            try GraphValidator.validate(restored)
            configuration = restored
        } else {
            configuration = MixerConfiguration()
        }
    }

    public static func defaultFileURL(bundleIdentifier: String) -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    @discardableResult
    public func update(
        discoveredDevices: [AudioDeviceDescriptor] = [],
        _ edit: (inout MixerConfiguration) throws -> Void
    ) throws -> MixerConfiguration {
        var candidate = configuration
        try edit(&candidate)
        candidate.reconcileKnownDevices(with: discoveredDevices)
        try GraphValidator.validate(candidate)
        guard candidate != configuration else { return configuration }

        let data = try JSONEncoder().encode(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        configuration = candidate
        return configuration
    }
}
