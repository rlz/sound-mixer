import Foundation

/// The rendering properties of a bus. Its display name does not affect audio.
public struct RuntimeBusRenderingDefinition: Equatable, Sendable {
    public let id: UUID
    public let mix: Mix
}

/// The configuration that determines one output renderer. Gain changes are applied
/// in place by the coordinator before it considers replacing a renderer.
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
            var mix = output.mix
            mix.level = 1
            routes["output:\(output.deviceUID.rawValue)"] = RuntimeRouteRenderingDefinition(
                deviceUID: output.deviceUID,
                channels: [0, 1],
                mix: mix,
                dependentBuses: Self.dependencies(of: mix, in: buses)
            )
        }
        for route in configuration.blackHoleRoutes {
            guard !route.mix.inputs.isEmpty else { continue }
            let channels: [Int] = switch route.channels {
            case let .mono(channel): [channel - 1]
            case let .stereo(left, right): [left - 1, right - 1]
            }
            routes["blackhole:\(route.id.uuidString)"] = RuntimeRouteRenderingDefinition(
                deviceUID: route.deviceUID,
                channels: channels,
                mix: route.mix,
                dependentBuses: Self.dependencies(of: route.mix, in: buses)
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
            busesByID[id].map { RuntimeBusRenderingDefinition(id: id, mix: $0.mix) }
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
