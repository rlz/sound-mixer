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
    case busCycle
    case invalidChannels
    case blackHoleChannelConflict(DeviceUID)
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
        try validateMixes(configuration)
        try validateBusGraph(configuration.buses)
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
            if !(1 ... 2).contains(device.inputChannels) {
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
            if device.outputChannels < 2 {
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
        let mixes = configuration.outputMixes.map(\.mix) + configuration.buses.map(\.mix) + configuration.blackHoleRoutes.map(\.mix)
        for mix in mixes {
            try validateLevel(mix.level)
            var sources = Set<SourceKey>()
            for input in mix.inputs {
                try validateLevel(input.level)
                let key = SourceKey(input.source)
                guard sources.insert(key).inserted else { throw GraphValidationError.duplicateSource }
                switch input.source {
                case let .bus(id):
                    guard busIDs.contains(id) else { throw GraphValidationError.missingBus(id) }
                case let .inputDevice(uid):
                    guard !uid.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
                case let .application(id):
                    guard !id.rawValue.isEmpty else { throw GraphValidationError.emptyIdentifier }
                }
            }
        }
    }

    private static func validateLevel(_ level: Double) throws {
        guard level.isFinite, (0 ... 1).contains(level) else { throw GraphValidationError.invalidLevel }
    }

    private static func validateBusGraph(_ buses: [VirtualBus]) throws {
        let dependencies = Dictionary(uniqueKeysWithValues: buses.map { bus in
            (bus.id, bus.mix.inputs.compactMap { input -> UUID? in
                if case let .bus(id) = input.source {
                    return id
                }
                return nil
            })
        })
        var visited = Set<UUID>()
        var visiting = Set<UUID>()

        func visit(_ id: UUID) throws {
            if visiting.contains(id) {
                throw GraphValidationError.busCycle
            }
            if visited.contains(id) {
                return
            }
            visiting.insert(id)
            for dependency in dependencies[id, default: []] {
                try visit(dependency)
            }
            visiting.remove(id)
            visited.insert(id)
        }

        for bus in buses {
            try visit(bus.id)
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

    init(_ source: SourceReference) {
        switch source {
        case let .inputDevice(uid): self = .inputDevice(uid)
        case let .application(id): self = .application(id)
        case let .bus(id): self = .bus(id)
        }
    }
}
