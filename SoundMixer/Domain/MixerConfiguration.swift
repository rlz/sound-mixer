import Foundation

/// A persisted Core Audio UID. Names and live AudioObjectIDs belong to discovery.
public struct DeviceUID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ApplicationID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AudioDeviceDescriptor: Equatable, Sendable {
    public let uid: DeviceUID
    public let name: String
    public let inputChannels: Int
    public let outputChannels: Int
    public let sampleRate: Double
    public let isBlackHole: Bool

    public init(uid: DeviceUID, name: String, inputChannels: Int, outputChannels: Int, sampleRate: Double, isBlackHole: Bool) {
        self.uid = uid
        self.name = name
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
        self.isBlackHole = isBlackHole
    }
}

public struct ApplicationDescriptor: Equatable, Sendable {
    public let id: ApplicationID
    public let name: String
    public let isAvailable: Bool

    public init(id: ApplicationID, name: String, isAvailable: Bool) {
        self.id = id
        self.name = name
        self.isAvailable = isAvailable
    }
}

public enum SourceReference: Hashable, Sendable {
    case inputDevice(DeviceUID)
    case application(ApplicationID)
    case bus(UUID)
    case blackHoleRoute(UUID)
}

extension SourceReference: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case id
    }

    private enum Kind: String, Codable {
        case inputDevice
        case application
        case bus
        case blackHoleRoute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inputDevice:
            self = try .inputDevice(DeviceUID(rawValue: container.decode(String.self, forKey: .id)))
        case .application:
            self = try .application(ApplicationID(rawValue: container.decode(String.self, forKey: .id)))
        case .bus:
            self = try .bus(container.decode(UUID.self, forKey: .id))
        case .blackHoleRoute:
            self = try .blackHoleRoute(container.decode(UUID.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inputDevice(uid):
            try container.encode(Kind.inputDevice, forKey: .kind)
            try container.encode(uid.rawValue, forKey: .id)
        case let .application(id):
            try container.encode(Kind.application, forKey: .kind)
            try container.encode(id.rawValue, forKey: .id)
        case let .bus(id):
            try container.encode(Kind.bus, forKey: .kind)
            try container.encode(id, forKey: .id)
        case let .blackHoleRoute(id):
            try container.encode(Kind.blackHoleRoute, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

public enum MonoPlacement: String, Codable, Sendable {
    case left
    case right
    case both
}

public struct MixInput: Codable, Equatable, Sendable {
    public static let maximumApplicationGain = pow(10.0, 30.0 / 20.0)

    public var source: SourceReference
    public var level: Double
    public var isMuted: Bool
    /// One-based destination channel numbers for each source channel.
    public var channelRouting: [[Int]]
    public var channelLevels: [Double]
    public var channelsLinked: Bool

    private enum CodingKeys: String, CodingKey {
        case source, level, isMuted, channelRouting, channelLevels, channelsLinked
    }

    private enum LegacyRouting: String, Codable {
        case ignore, first, second, both

        var channels: [Int] {
            switch self {
            case .ignore: []
            case .first: [1]
            case .second: [2]
            case .both: [1, 2]
            }
        }
    }

    public init(
        source: SourceReference,
        level: Double = 1,
        isMuted: Bool = false,
        channelRouting: [[Int]] = [[1], [2]],
        channelLevels: [Double] = [1, 1],
        channelsLinked: Bool = true
    ) {
        self.source = source
        self.level = level
        self.isMuted = isMuted
        self.channelRouting = channelRouting
        self.channelLevels = channelLevels
        self.channelsLinked = channelsLinked
    }

    public static func defaultRouting(channelCount: Int, outputChannels: Int) -> [[Int]] {
        (0 ..< max(0, channelCount)).map { channel in
            if channelCount == 1 {
                return outputChannels > 0 ? Array(1 ... min(outputChannels, 2)) : []
            }
            return channel < min(outputChannels, 2) ? [channel + 1] : []
        }
    }

    public static func physicalInputDefaults(channelCount: Int, outputChannels: Int = 2) -> (routing: [[Int]], levels: [Double]) {
        let routing = defaultRouting(channelCount: channelCount, outputChannels: outputChannels)
        return (routing, Array(repeating: 1, count: routing.count))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(SourceReference.self, forKey: .source)
        level = try container.decode(Double.self, forKey: .level)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        if let matrix = try? container.decode([[Int]].self, forKey: .channelRouting) {
            channelRouting = matrix
        } else {
            let legacy = try container.decode([LegacyRouting].self, forKey: .channelRouting)
            channelRouting = legacy.map(\.channels)
        }
        channelLevels = try container.decode([Double].self, forKey: .channelLevels)
        channelsLinked = try container.decode(Bool.self, forKey: .channelsLinked)
        if channelRouting.isEmpty {
            switch source {
            case .inputDevice:
                channelRouting = [[1, 2]]
                channelLevels = [1]
            case .application, .bus, .blackHoleRoute:
                channelRouting = Self.defaultRouting(channelCount: 2, outputChannels: 2)
                channelLevels = [1, 1]
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(level, forKey: .level)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(channelRouting, forKey: .channelRouting)
        try container.encode(channelLevels, forKey: .channelLevels)
        try container.encode(channelsLinked, forKey: .channelsLinked)
    }
}

public struct Mix: Codable, Equatable, Sendable {
    public var level: Double
    public var inputs: [MixInput]

    public init(level: Double = 1, inputs: [MixInput] = []) {
        self.level = level
        self.inputs = inputs
    }
}

public struct OutputMix: Codable, Equatable, Sendable {
    public var deviceUID: DeviceUID
    public var mix: Mix

    public init(deviceUID: DeviceUID, mix: Mix = Mix()) {
        self.deviceUID = deviceUID
        self.mix = mix
    }
}

public struct VirtualBus: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var mix: Mix

    public init(id: UUID = UUID(), name: String, mix: Mix = Mix()) {
        self.id = id
        self.name = name
        self.mix = mix
    }
}

public enum BlackHoleChannels: Equatable, Sendable {
    case mono(Int)
    case stereo(left: Int, right: Int)
}

extension BlackHoleChannels: Codable {
    private enum CodingKeys: String, CodingKey {
        case mode
        case channels
    }

    private enum Mode: String, Codable {
        case mono
        case stereo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        let channels = try container.decode([Int].self, forKey: .channels)
        switch mode {
        case .mono where channels.count == 1:
            self = .mono(channels[0])
        case .stereo where channels.count == 2:
            self = .stereo(left: channels[0], right: channels[1])
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .channels,
                in: container,
                debugDescription: "Channel count does not match mode"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .mono(channel):
            try container.encode(Mode.mono, forKey: .mode)
            try container.encode([channel], forKey: .channels)
        case let .stereo(left, right):
            try container.encode(Mode.stereo, forKey: .mode)
            try container.encode([left, right], forKey: .channels)
        }
    }
}

public struct BlackHoleRoute: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var deviceUID: DeviceUID
    public var channels: BlackHoleChannels
    public var mix: Mix

    public init(id: UUID = UUID(), name: String, deviceUID: DeviceUID, channels: BlackHoleChannels, mix: Mix = Mix()) {
        self.id = id
        self.name = name
        self.deviceUID = deviceUID
        self.channels = channels
        self.mix = mix
    }
}

public struct KnownDevice: Codable, Equatable, Sendable {
    public var uid: DeviceUID
    public var lastKnownName: String?

    public init(uid: DeviceUID, lastKnownName: String? = nil) {
        self.uid = uid
        self.lastKnownName = lastKnownName
    }
}

public struct SourceLevel: Codable, Equatable, Sendable {
    public var source: SourceReference
    public var level: Double

    public init(source: SourceReference, level: Double = 1) {
        self.source = source
        self.level = level
    }
}

public struct MixerConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 10

    public let schemaVersion: Int
    public var isEnabled: Bool
    public var outputMixes: [OutputMix]
    public var buses: [VirtualBus]
    public var blackHoleRoutes: [BlackHoleRoute]
    public var knownDevices: [KnownDevice]
    public var mutedSources: [SourceReference]
    public var mutedBuses: [UUID]
    public var applications: [ApplicationID]
    public var sourceLevels: [SourceLevel]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case outputMixes
        case buses
        case blackHoleRoutes
        case knownDevices
        case mutedSources
        case mutedBuses
        case applications
        case sourceLevels
    }

    public init(
        isEnabled: Bool = false,
        outputMixes: [OutputMix] = [],
        buses: [VirtualBus] = [],
        blackHoleRoutes: [BlackHoleRoute] = [],
        knownDevices: [KnownDevice] = [],
        mutedSources: [SourceReference] = [],
        mutedBuses: [UUID] = [],
        applications: [ApplicationID] = [],
        sourceLevels: [SourceLevel] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.isEnabled = isEnabled
        self.outputMixes = outputMixes
        self.buses = buses
        self.blackHoleRoutes = blackHoleRoutes
        self.knownDevices = knownDevices
        self.mutedSources = mutedSources
        self.mutedBuses = mutedBuses
        self.applications = applications
        self.sourceLevels = sourceLevels
        reconcileKnownDevices(with: [])
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion || version == 9 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported configuration schema version \(version)"
            )
        }

        schemaVersion = Self.currentSchemaVersion
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        outputMixes = try container.decode([OutputMix].self, forKey: .outputMixes)
        buses = try container.decode([VirtualBus].self, forKey: .buses)
        blackHoleRoutes = try container.decode([BlackHoleRoute].self, forKey: .blackHoleRoutes)
        knownDevices = try container.decode([KnownDevice].self, forKey: .knownDevices)
        mutedSources = try container.decode([SourceReference].self, forKey: .mutedSources)
        mutedBuses = try container.decode([UUID].self, forKey: .mutedBuses)
        guard Set(mutedBuses).count == mutedBuses.count else {
            throw DecodingError.dataCorruptedError(forKey: .mutedBuses, in: container, debugDescription: "Muted buses must be unique")
        }
        applications = try container.decode([ApplicationID].self, forKey: .applications)
        sourceLevels = try container.decode([SourceLevel].self, forKey: .sourceLevels)
        guard sourceLevels.allSatisfy({
            let maximum = if case .application = $0.source {
                MixInput.maximumApplicationGain
            } else {
                1.0
            }
            return $0.level.isFinite && (0 ... maximum).contains($0.level)
        }),
            Set(sourceLevels.map(\.source)).count == sourceLevels.count
        else {
            throw DecodingError.dataCorruptedError(forKey: .sourceLevels, in: container, debugDescription: "Source levels must be unique and in range")
        }
        guard Set(applications).count == applications.count else {
            throw DecodingError.dataCorruptedError(forKey: .applications, in: container, debugDescription: "Registered applications must be unique")
        }
        guard mutedSources.allSatisfy({
            if case .bus = $0 {
                false
            } else {
                true
            }
        }),
            Set(mutedSources).count == mutedSources.count
        else {
            throw DecodingError.dataCorruptedError(forKey: .mutedSources, in: container, debugDescription: "Muted sources must be unique input or application sources")
        }
        let uids = knownDevices.map(\.uid)
        guard Set(uids).count == uids.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .knownDevices,
                in: container,
                debugDescription: "Duplicate device UID metadata"
            )
        }
        reconcileKnownDevices(with: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(outputMixes, forKey: .outputMixes)
        try container.encode(buses, forKey: .buses)
        try container.encode(blackHoleRoutes, forKey: .blackHoleRoutes)
        try container.encode(knownDevices, forKey: .knownDevices)
        try container.encode(mutedSources, forKey: .mutedSources)
        try container.encode(mutedBuses, forKey: .mutedBuses)
        try container.encode(applications, forKey: .applications)
        try container.encode(sourceLevels, forKey: .sourceLevels)
    }

    public func deviceDisplayName(for uid: DeviceUID) -> String {
        knownDevices.first(where: { $0.uid == uid })?.lastKnownName ?? uid.rawValue
    }

    /// Refresh metadata only for configured devices; discovery never creates saved ghosts.
    public mutating func reconcileKnownDevices(with discoveredDevices: [AudioDeviceDescriptor]) {
        var referencedUIDs = Set(outputMixes.map(\.deviceUID))
        referencedUIDs.formUnion(blackHoleRoutes.map(\.deviceUID))
        for mix in outputMixes.map(\.mix) + buses.map(\.mix) + blackHoleRoutes.map(\.mix) {
            for input in mix.inputs {
                if case let .inputDevice(uid) = input.source {
                    referencedUIDs.insert(uid)
                }
            }
        }

        let savedNames = knownDevices.reduce(into: [DeviceUID: String]()) { names, device in
            names[device.uid] = device.lastKnownName
        }
        let discoveredNames = discoveredDevices.reduce(into: [DeviceUID: String]()) { names, device in
            names[device.uid] = device.name
        }
        knownDevices = referencedUIDs.sorted { $0.rawValue < $1.rawValue }.map { uid in
            let currentName = discoveredNames[uid]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedName = savedNames[uid]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = [currentName, savedName].compactMap(\.self).first { !$0.isEmpty }
            return KnownDevice(uid: uid, lastKnownName: name)
        }
    }
}
