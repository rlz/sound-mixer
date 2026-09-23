import Foundation
#if SWIFT_PACKAGE
    import SoundMixerDomain
#endif

/// Owns the accepted configuration and publishes an edit only after its file is replaced.
public final class ConfigurationStore {
    public private(set) var configuration: MixerConfiguration
    public private(set) var activeGraph: MixGraphSnapshot
    public let fileURL: URL
    public private(set) var discardedInvalidConfiguration = false

    public enum LoadError: LocalizedError {
        case couldNotRemoveInvalidConfiguration(URL, Error)

        public var errorDescription: String? {
            switch self {
            case let .couldNotRemoveInvalidConfiguration(url, error):
                "The invalid configuration at \(url.path) could not be removed: \(error.localizedDescription)"
            }
        }
    }

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let restored = try JSONDecoder().decode(MixerConfiguration.self, from: data)
                let restoredGraph = try MixGraphSnapshot(configuration: restored)
                activeGraph = restoredGraph
                configuration = restored
            } catch {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    throw LoadError.couldNotRemoveInvalidConfiguration(fileURL, error)
                }
                let initial = MixerConfiguration()
                activeGraph = try MixGraphSnapshot(configuration: initial)
                configuration = initial
                discardedInvalidConfiguration = true
            }
        } else {
            let initial = MixerConfiguration()
            activeGraph = try MixGraphSnapshot(configuration: initial)
            configuration = initial
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
        let candidateGraph = try MixGraphSnapshot(configuration: candidate)
        guard candidate != configuration else { return configuration }

        let data = try JSONEncoder().encode(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        configuration = candidate
        activeGraph = candidateGraph
        return configuration
    }
}
