import Foundation

public enum GraphValidationError: Error, Equatable {
    case duplicateOutput(DeviceUID)
    case duplicateBus(UUID)
    case duplicateRoute(UUID)
    case duplicateSource
    case emptyIdentifier
    case emptyName
    case invalidLevel
    case missingBus(UUID)
    case missingRoute(UUID)
    case busCycle
    case invalidChannels
    case invalidChannelSettings
    case blackHoleChannelConflict(DeviceUID)
}

extension GraphValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .duplicateOutput(uid): "An output mix already exists for device \(uid.rawValue)."
        case let .duplicateBus(id): "A virtual bus already exists with ID \(id.uuidString)."
        case let .duplicateRoute(id): "A BlackHole route already exists with ID \(id.uuidString)."
        case .duplicateSource: "A source can appear only once in each mix."
        case .emptyIdentifier: "A device or source identifier cannot be empty."
        case .emptyName: "Names must contain at least one non-space character."
        case .invalidLevel: "Levels must be between 0 and 100 percent, except application gain, which can reach +30 dB."
        case let .missingBus(id): "The referenced virtual bus \(id.uuidString) no longer exists."
        case let .missingRoute(id): "The referenced BlackHole route \(id.uuidString) no longer exists."
        case .busCycle: "This change would create a cycle between virtual buses."
        case .invalidChannels: "Choose distinct channel numbers starting at 1."
        case .invalidChannelSettings: "Input routing and gain settings must have matching channel counts and valid channel numbers."
        case let .blackHoleChannelConflict(uid):
            "Those channels are already reserved by another route or output mix on \(uid.rawValue)."
        }
    }
}

public enum GraphEndpoint: Equatable {
    case input(DeviceUID)
    case output(DeviceUID)
    case blackHoleRoute(UUID)
}

public enum DeviceCompatibilityIssue: Equatable {
    case missingDevice(GraphEndpoint)
    case invalidSampleRate(GraphEndpoint)
    case unsupportedChannelCount(GraphEndpoint)
    case notBlackHole(GraphEndpoint)
    case channelOutOfRange(GraphEndpoint)
}

/// Structural checks run before accepting a configuration. Device checks run again before starting audio.
public enum GraphValidator {
    public static func validate(_ configuration: MixerConfiguration) throws {
        try validateIdentities(configuration)
        guard Set(configuration.sourceLevels.map(\.source)).count == configuration.sourceLevels.count else {
            throw GraphValidationError.duplicateSource
        }
        for sourceLevel in configuration.sourceLevels {
            if case .application = sourceLevel.source {
                try validateLevel(sourceLevel.level, maximum: MixInput.maximumApplicationGain)
            } else {
                try validateLevel(sourceLevel.level)
            }
        }
        try validateMixes(configuration)
        try validateMixGraph(configuration)
        try validateBlackHoleReservations(configuration)
    }

    public static func deviceIssues(
        for configuration: MixerConfiguration,
        devices: [AudioDeviceDescriptor]
    ) -> [DeviceCompatibilityIssue] {
        let discovered = Dictionary(devices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        var issues: [DeviceCompatibilityIssue] = []

        for uid in inputUIDs(in: configuration).sorted(by: { $0.rawValue < $1.rawValue }) {
            let endpoint = GraphEndpoint.input(uid)
            guard let device = discovered[uid] else {
                issues.append(.missingDevice(endpoint))
                continue
            }
            appendSampleRateIssue(for: device, endpoint: endpoint, to: &issues)
            if !(1 ... 64).contains(device.inputChannels) {
                issues.append(.unsupportedChannelCount(endpoint))
            }
        }

        for output in configuration.outputMixes {
            let endpoint = GraphEndpoint.output(output.deviceUID)
            guard let device = discovered[output.deviceUID] else {
                issues.append(.missingDevice(endpoint))
                continue
            }
            appendSampleRateIssue(for: device, endpoint: endpoint, to: &issues)
            if device.outputChannels < 1 {
                issues.append(.unsupportedChannelCount(endpoint))
            }
        }

        for route in configuration.blackHoleRoutes {
            let endpoint = GraphEndpoint.blackHoleRoute(route.id)
            guard let device = discovered[route.deviceUID] else {
                issues.append(.missingDevice(endpoint))
                continue
            }
            appendSampleRateIssue(for: device, endpoint: endpoint, to: &issues)
            if !device.isBlackHole {
                issues.append(.notBlackHole(endpoint))
            }
            if selectedChannels(route.channels).contains(where: { $0 > device.outputChannels }) {
                issues.append(.channelOutOfRange(endpoint))
            }
        }

        return issues
    }

    private static func validateIdentities(_ configuration: MixerConfiguration) throws {
        var outputs = Set<DeviceUID>()
        var buses = Set<UUID>()
        var routes = Set<UUID>()

        for output in configuration.outputMixes {
            guard !output.deviceUID.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
            guard outputs.insert(output.deviceUID).inserted else { throw GraphValidationError.duplicateOutput(output.deviceUID) }
        }
        for bus in configuration.buses {
            guard buses.insert(bus.id).inserted else { throw GraphValidationError.duplicateBus(bus.id) }
            guard !bus.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GraphValidationError.emptyName }
        }
        for route in configuration.blackHoleRoutes {
            guard routes.insert(route.id).inserted else { throw GraphValidationError.duplicateRoute(route.id) }
            guard !route.deviceUID.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
            guard !route.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GraphValidationError.emptyName }
        }
    }

    private static func validateMixes(_ configuration: MixerConfiguration) throws {
        let busIDs = Set(configuration.buses.map(\.id))
        let routeIDs = Set(configuration.blackHoleRoutes.map(\.id))
        let mixes = configuration.outputMixes.map(\.mix) + configuration.buses.map(\.mix) + configuration.blackHoleRoutes.map(\.mix)
        for mix in mixes {
            try validateLevel(mix.level)
            var sources = Set<SourceKey>()
            for input in mix.inputs {
                try validateLevel(input.level)
                guard (1 ... 64).contains(input.channelRouting.count),
                      input.channelRouting.count == input.channelLevels.count,
                      input.channelRouting.allSatisfy({ row in
                          Set(row).count == row.count && row.allSatisfy { $0 > 0 }
                      })
                else {
                    throw GraphValidationError.invalidChannelSettings
                }
                for channelLevel in input.channelLevels {
                    try validateLevel(channelLevel)
                }
                let key = SourceKey(input.source)
                guard sources.insert(key).inserted else { throw GraphValidationError.duplicateSource }
                switch input.source {
                case let .bus(id):
                    guard busIDs.contains(id) else { throw GraphValidationError.missingBus(id) }
                case let .blackHoleRoute(id):
                    guard routeIDs.contains(id) else { throw GraphValidationError.missingRoute(id) }
                case let .inputDevice(uid):
                    guard !uid.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
                case let .application(id):
                    guard !id.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
                }
            }
        }
    }

    private static func validateLevel(_ level: Double, maximum: Double = 1) throws {
        guard level.isFinite, (0 ... maximum).contains(level) else { throw GraphValidationError.invalidLevel }
    }

    private static func validateMixGraph(_ configuration: MixerConfiguration) throws {
        let nodes = configuration.buses.map { MixNode.bus($0.id, $0.mix) }
            + configuration.blackHoleRoutes.map { MixNode.route($0.id, $0.mix) }
        let nodeIDs = Set(nodes.map(\.id))
        let dependencies = Dictionary(uniqueKeysWithValues: nodes.map { node in
            (node.id, node.mix.inputs.compactMap { input -> MixNode.ID? in
                switch input.source {
                case let .bus(id): MixNode.ID.bus(id)
                case let .blackHoleRoute(id): MixNode.ID.route(id)
                case .inputDevice, .application: nil
                }
            })
        })
        var visited = Set<MixNode.ID>()
        var visiting = Set<MixNode.ID>()

        func visit(_ id: MixNode.ID) throws {
            if visiting.contains(id) {
                throw GraphValidationError.busCycle
            }
            if visited.contains(id) {
                return
            }
            visiting.insert(id)
            for dependency in dependencies[id, default: []] where nodeIDs.contains(dependency) {
                try visit(dependency)
            }
            visiting.remove(id)
            visited.insert(id)
        }

        for node in nodes {
            try visit(node.id)
        }
    }

    private static func validateBlackHoleReservations(_ configuration: MixerConfiguration) throws {
        let baseMixUIDs = Set(configuration.outputMixes.map(\.deviceUID))
        var reserved = [DeviceUID: Set<Int>]()
        for route in configuration.blackHoleRoutes {
            let channels = selectedChannels(route.channels)
            guard channels.allSatisfy({ $0 > 0 }), Set(channels).count == channels.count else {
                throw GraphValidationError.invalidChannels
            }
            var used = reserved[route.deviceUID, default: []]
            guard !baseMixUIDs.contains(route.deviceUID), used.isDisjoint(with: channels) else {
                throw GraphValidationError.blackHoleChannelConflict(route.deviceUID)
            }
            used.formUnion(channels)
            reserved[route.deviceUID] = used
        }
    }

    private static func selectedChannels(_ channels: BlackHoleChannels) -> [Int] {
        switch channels {
        case let .mono(channel): [channel]
        case let .stereo(left, right): [left, right]
        }
    }

    private static func inputUIDs(in configuration: MixerConfiguration) -> Set<DeviceUID> {
        let mixes = configuration.outputMixes.map(\.mix) + configuration.buses.map(\.mix) + configuration.blackHoleRoutes.map(\.mix)
        return Set(mixes.flatMap(\.inputs).compactMap { input in
            if case let .inputDevice(uid) = input.source {
                return uid
            }
            return nil
        })
    }

    private static func appendSampleRateIssue(
        for device: AudioDeviceDescriptor,
        endpoint: GraphEndpoint,
        to issues: inout [DeviceCompatibilityIssue]
    ) {
        if !device.sampleRate.isFinite || device.sampleRate <= 0 {
            issues.append(.invalidSampleRate(endpoint))
        }
    }
}

/// Immutable, validated render description. Bus order is dependency-first so a renderer
/// can calculate each shared bus once before consuming mixes are processed.
public struct MixGraphSnapshot: Equatable, Sendable {
    public let configuration: MixerConfiguration
    public let busRenderOrder: [UUID]

    public init(configuration: MixerConfiguration) throws {
        try GraphValidator.validate(configuration)
        self.configuration = configuration
        busRenderOrder = Self.dependencyFirstOrder(configuration.buses)
    }

    private static func dependencyFirstOrder(_ buses: [VirtualBus]) -> [UUID] {
        let byID = Dictionary(uniqueKeysWithValues: buses.map { ($0.id, $0) })
        var visited = Set<UUID>()
        var order: [UUID] = []

        func visit(_ id: UUID) {
            guard visited.insert(id).inserted, let bus = byID[id] else { return }
            for input in bus.mix.inputs {
                if case let .bus(dependency) = input.source {
                    visit(dependency)
                }
            }
            order.append(id)
        }

        for bus in buses {
            visit(bus.id)
        }
        return order
    }
}

private enum SourceKey: Hashable {
    case inputDevice(DeviceUID)
    case application(ApplicationID)
    case bus(UUID)
    case blackHoleRoute(UUID)

    init(_ source: SourceReference) {
        switch source {
        case let .inputDevice(uid): self = .inputDevice(uid)
        case let .application(id): self = .application(id)
        case let .bus(id): self = .bus(id)
        case let .blackHoleRoute(id): self = .blackHoleRoute(id)
        }
    }
}

private enum MixNode {
    enum ID: Hashable { case bus(UUID); case route(UUID) }
    case bus(UUID, Mix)
    case route(UUID, Mix)

    var id: ID {
        switch self {
        case let .bus(id, _): .bus(id)
        case let .route(id, _): .route(id)
        }
    }

    var mix: Mix {
        switch self {
        case let .bus(_, mix), let .route(_, mix): mix
        }
    }
}
