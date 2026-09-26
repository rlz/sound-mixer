import Foundation

/// The rendering properties of a bus. Its display name does not affect audio.
public struct RuntimeBusRenderingDefinition: Equatable, Sendable {
    public let id: UUID
    public let channelCount: Int
    public let mix: Mix
}

/// The structure that determines one output renderer. Gains are excluded because
/// they are published to existing renderers, including during device reconciliation.
public struct RuntimeRouteRenderingDefinition: Equatable, Sendable {
    public let deviceUID: DeviceUID
    public let channels: [Int]
    public let mix: Mix
    public let dependentBuses: [RuntimeBusRenderingDefinition]
}

/// A pure description of the desired render graph. Runtime resource availability is
/// checked separately, so a failed or missing session is never mistaken for an active one.
public struct RuntimeGraphShape: Equatable, Sendable {
    public let routesByKey: [String: RuntimeRouteRenderingDefinition]
    public let busDependenciesByID: [UUID: [RuntimeBusRenderingDefinition]]

    public init(configuration: MixerConfiguration) {
        let buses = configuration.buses
        var routes: [String: RuntimeRouteRenderingDefinition] = [:]
        for output in configuration.outputMixes {
            let mix = Self.renderingStructure(output.mix)
            routes["output:\(output.deviceUID.rawValue)"] = RuntimeRouteRenderingDefinition(
                deviceUID: output.deviceUID,
                // Physical channel count comes from the live device descriptor.
                channels: [],
                mix: mix,
                dependentBuses: Self.dependencies(of: mix, in: buses)
            )
        }
        routesByKey = routes
        busDependenciesByID = Dictionary(uniqueKeysWithValues: buses.map { bus in
            (bus.id, Self.dependencies(of: Mix(inputs: [MixInput(source: .bus(bus.id))]), in: buses))
        })
    }

    public func changedRouteKeys(from previous: RuntimeGraphShape) -> Set<String> {
        Set(routesByKey.keys).union(previous.routesByKey.keys).filter {
            routesByKey[$0] != previous.routesByKey[$0]
        }
    }

    public func changedBusIDs(from previous: RuntimeGraphShape) -> Set<UUID> {
        Set(busDependenciesByID.keys).union(previous.busDependenciesByID.keys).filter {
            busDependenciesByID[$0] != previous.busDependenciesByID[$0]
        }
    }

    public static func hasOnlyEmptyBusChanges(from old: MixerConfiguration, to new: MixerConfiguration) -> Bool {
        func normalized(_ configuration: MixerConfiguration) -> MixerConfiguration {
            var copy = configuration
            copy.buses.removeAll { $0.mix.inputs.isEmpty }
            copy.buses.sort { $0.id.uuidString < $1.id.uuidString }
            let remainingIDs = Set(copy.buses.map(\.id))
            copy.mutedBuses = copy.mutedBuses.filter { remainingIDs.contains($0) }
            return copy
        }
        return normalized(old) == normalized(new)
    }

    private static func dependencies(of mix: Mix, in buses: [VirtualBus]) -> [RuntimeBusRenderingDefinition] {
        let busesByID = Dictionary(uniqueKeysWithValues: buses.map { ($0.id, $0) })
        var pending = mix.inputs.compactMap { input -> UUID? in
            guard case let .bus(id) = input.source else { return nil }
            return id
        }
        var visited = Set<UUID>()
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let bus = busesByID[id] else { continue }
            pending += bus.mix.inputs.compactMap { input -> UUID? in
                guard case let .bus(dependencyID) = input.source else { return nil }
                return dependencyID
            }
        }
        return visited.compactMap { id in
            busesByID[id].map { RuntimeBusRenderingDefinition(id: id, channelCount: $0.channelCount, mix: renderingStructure($0.mix)) }
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func renderingStructure(_ mix: Mix) -> Mix {
        var result = mix
        result.level = 1
        for index in result.inputs.indices {
            result.inputs[index].level = 1
            result.inputs[index].isMuted = false
            // Channel count remains structural: it determines preallocated engines.
            result.inputs[index].channelLevels = Array(repeating: 1, count: result.inputs[index].channelLevels.count)
            result.inputs[index].channelRouting = Array(repeating: [], count: result.inputs[index].channelRouting.count)
        }
        return result
    }
}

/// A transient process identity used only to decide whether capture needs reconciliation.
public struct RuntimeProcessRoutingIdentity: Hashable, Sendable {
    public let applicationID: String
    public let processID: Int32
    public let isProducingOutput: Bool

    public init(applicationID: String, processID: Int32, isProducingOutput: Bool) {
        self.applicationID = applicationID
        self.processID = processID
        self.isProducingOutput = isProducingOutput
    }

    public static func matches(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        // Several audio processes can share a bundle ID. Preserve every PID and
        // duplicate entry while ignoring discovery order.
        return Dictionary(grouping: lhs, by: { $0 }).mapValues { $0.count } ==
            Dictionary(grouping: rhs, by: { $0 }).mapValues { $0.count }
    }
}
