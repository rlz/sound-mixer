import Foundation
import Synchronization

/// Renders one configured output from a validated graph. Source queues are drained
/// once per block, and each shared bus is rendered once in dependency order.
final class AudioGraphRenderer {
    private let outputMix: Mix
    private let targetKey: String
    private let busesByID: [UUID: VirtualBus]
    private let busOrder: [UUID]
    private let sourceRings: [String: RealtimeAudioRingBuffer]
    private let sourceBuffers: [String: MultiChannelStorage]
    private let sourceReferences: Set<SourceReference>
    private let busBuffers: [UUID: MultiChannelStorage]
    private let sourceKeys: [String]
    private let mixStates: [UUID: [MixInputState]]
    private let outputState: [MixInputState]
    private let mutedSources: Set<SourceReference>
    private let busMuteStates: [UUID: BusMuteState]
    private let busDestinationMeters: [UUID: RealtimePeakMeter]
    private let busChannelMeters: [UUID: [RealtimePeakMeter]]
    private let outputDestinationMeter: RealtimePeakMeter?
    private static let maximumFrames = 8192

    init(
        graph: MixGraphSnapshot,
        output: OutputMix,
        sourceRings: [String: RealtimeAudioRingBuffer],
        outputChannelCount: Int = 2,
        targetKey: String,
        meters: [String: RealtimePeakMeter]
    ) {
        outputMix = output.mix
        self.targetKey = targetKey
        mutedSources = Set(graph.configuration.mutedSources)
        let allBusesByID = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { ($0.id, $0) })
        let relevantBusIDs = busDependencies(for: output.mix, in: allBusesByID)
        let relevantBuses = graph.configuration.buses.filter { relevantBusIDs.contains($0.id) }
        let relevantBusOrder = graph.busRenderOrder.filter { relevantBusIDs.contains($0) }
        busMuteStates = Dictionary(uniqueKeysWithValues: relevantBuses.map {
            ($0.id, BusMuteState(Set(graph.configuration.mutedBuses).contains($0.id)))
        })
        busDestinationMeters = Dictionary(uniqueKeysWithValues: relevantBuses.map {
            ($0.id, meters["bus:\($0.id.uuidString)/destination"])
        }.compactMap { key, meter in meter.map { (key, $0) } })
        busChannelMeters = Dictionary(uniqueKeysWithValues: relevantBuses.map { bus in
            (bus.id, (0 ..< bus.channelCount).compactMap { meters["bus:\(bus.id.uuidString)/channel/\($0 + 1)"] })
        })
        outputDestinationMeter = meters["\(targetKey)/destination"]
        busesByID = Dictionary(uniqueKeysWithValues: relevantBuses.map { ($0.id, $0) })
        busOrder = relevantBusOrder
        self.sourceRings = sourceRings

        let mixes = relevantBuses.map(\.mix) + [output.mix]
        sourceReferences = nonBusSources(in: mixes)
        let sources = Set(mixes.flatMap(\.inputs).compactMap { input -> String? in
            guard case .bus = input.source else { return Self.sourceKey(input.source) }
            return nil
        })
        sourceKeys = sources.sorted()
        sourceBuffers = Dictionary(uniqueKeysWithValues: sourceKeys.map { key in
            (key, MultiChannelStorage(capacity: Self.maximumFrames, channelCount: sourceRings[key]?.channelCount ?? 2))
        })
        busBuffers = Dictionary(uniqueKeysWithValues: busOrder.compactMap { id in
            allBusesByID[id].map { (id, MultiChannelStorage(capacity: Self.maximumFrames, channelCount: $0.channelCount)) }
        })
        mixStates = Dictionary(uniqueKeysWithValues: relevantBuses.map { bus in
            (
                bus.id,
                Self.states(
                    for: bus.mix, sampleRate: 48000,
                    meterTarget: "bus:\(bus.id.uuidString)", meters: meters, outputChannelCount: bus.channelCount
                )
            )
        })
        outputState = Self.states(
            for: output.mix, sampleRate: 48000,
            meterTarget: targetKey, meters: meters, outputChannelCount: outputChannelCount
        )
    }

    func render(channels: UnsafeBufferPointer<UnsafeMutablePointer<Float>>, frameCount: Int) {
        let frames = min(frameCount, Self.maximumFrames)
        guard frames > 0 else { return }
        for pointer in channels {
            pointer.update(repeating: 0, count: frames)
        }

        for key in sourceKeys {
            guard let storage = sourceBuffers[key] else { continue }
            storage.clear(frames: frames)
            _ = sourceRings[key]?.read(channels: storage.mutablePlanePointers, frameCount: frames)
        }

        for busID in busOrder {
            guard let bus = busesByID[busID], let storage = busBuffers[busID],
                  let states = mixStates[busID]
            else { continue }
            storage.clear(frames: frames)
            renderMix(bus.mix, states: states, into: storage, frames: frames)
            if busMuteStates[busID]?.value.load(ordering: .relaxed) == true {
                storage.clear(frames: frames)
            }
            busDestinationMeters[busID]?.record(
                left: storage.readChannel(0, frames: frames),
                right: storage.readChannel(min(1, bus.channelCount - 1), frames: frames), frameCount: frames
            )
            for channel in 0 ..< min(bus.channelCount, busChannelMeters[busID]?.count ?? 0) {
                busChannelMeters[busID]?[channel].record(samples: storage.readChannel(channel, frames: frames))
            }
        }

        renderMix(outputMix, states: outputState, into: channels, frames: frames)
        var peak: Float = 0
        for pointer in channels {
            for frame in 0 ..< frames {
                peak = max(peak, abs(pointer[frame]))
            }
        }
        outputDestinationMeter?.record(peak: peak)
    }

    /// Publishes gain changes to the render thread without rebuilding its audio graph.
    func updateGains(from graph: MixGraphSnapshot) {
        let mutedBusIDs = Set(graph.configuration.mutedBuses)
        for (id, state) in busMuteStates {
            state.value.store(mutedBusIDs.contains(id), ordering: .relaxed)
        }
        let busMixes = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { ($0.id, $0.mix) })
        let mutedSources = Set(graph.configuration.mutedSources).union(
            graph.configuration.hiddenDeviceUIDs.map(SourceReference.inputDevice)
        )
        let sourceLevels = graph.configuration.sourceLevels
        for (id, states) in mixStates {
            guard let mix = busMixes[id] else { continue }
            Self.update(states: states, mix: mix, mutedSources: mutedSources, sourceLevels: sourceLevels)
        }
        let mix = graph.configuration.outputMixes.first(where: { targetKey == "output:\($0.deviceUID.rawValue)" })?.mix
        if let mix {
            Self.update(states: outputState, mix: mix, mutedSources: mutedSources, sourceLevels: sourceLevels)
        }
    }

    /// A matrix edit changes only the connections of rows whose assignments changed.
    func updateRouting(from graph: MixGraphSnapshot, previous: MixGraphSnapshot) {
        let oldBuses = Dictionary(uniqueKeysWithValues: previous.configuration.buses.map { ($0.id, $0.mix) })
        for bus in graph.configuration.buses {
            guard let old = oldBuses[bus.id], let states = mixStates[bus.id] else { continue }
            Self.publishRouting(from: bus.mix, previous: old, states: states)
        }
        let oldMix = previous.configuration.outputMixes.first(where: { targetKey == "output:\($0.deviceUID.rawValue)" })?.mix
        let newMix = graph.configuration.outputMixes.first(where: { targetKey == "output:\($0.deviceUID.rawValue)" })?.mix
        if let oldMix, let newMix {
            Self.publishRouting(from: newMix, previous: oldMix, states: outputState)
        }
    }

    private static func publishRouting(from mix: Mix, previous: Mix, states: [MixInputState]) {
        for (index, input) in mix.inputs.enumerated() where index < min(previous.inputs.count, states.count) {
            guard input.channelRouting != previous.inputs[index].channelRouting else { continue }
            for channel in states[index].routing.indices {
                let selected = channel < input.channelRouting.count ? input.channelRouting[channel] : []
                for output in states[index].routing[channel].indices {
                    states[index].routing[channel][output].value.store(selected.contains(output + 1), ordering: .relaxed)
                }
            }
        }
    }

    func depends(on changedSources: Set<SourceReference>, changedBuses: Set<UUID>) -> Bool {
        !sourceReferences.isDisjoint(with: changedSources) ||
            !Set(busMuteStates.keys).isDisjoint(with: changedBuses)
    }

    private func renderMix(_ mix: Mix, states: [MixInputState], into storage: MultiChannelStorage, frames: Int) {
        renderMix(mix, states: states, into: storage.mutablePlanePointers, frames: frames)
    }

    private func renderMix(
        _ mix: Mix,
        states: [MixInputState],
        into destination: UnsafeBufferPointer<UnsafeMutablePointer<Float>>,
        frames: Int
    ) {
        for (index, input) in mix.inputs.enumerated() where index < states.count {
            let state = states[index]
            var rowPeak: Float = 0
            for channel in state.channelEngines.indices {
                let source: UnsafeBufferPointer<Float>
                if case let .bus(id) = input.source {
                    guard let storage = busBuffers[id], channel < storage.channelCount else { continue }
                    source = storage.readChannel(channel, frames: frames)
                } else {
                    guard let storage = sourceBuffers[state.sourceKey], channel < storage.channelCount else { continue }
                    source = storage.readChannel(channel, frames: frames)
                }
                for output in 0 ..< min(destination.count, state.channelEngines[channel].count) {
                    var engine = state.channelEngines[channel][output]
                    let selected = state.routing[channel][output].value.load(ordering: .relaxed)
                    if !selected, engine.currentSourceGain < 0.00001 {
                        continue
                    }
                    let gain = state.channelGains[channel].value.load(ordering: .relaxed)
                    engine.setSourceGain(selected ? gain : 0)
                    engine.setMainGain(state.mainGain.load(ordering: .relaxed))
                    rowPeak = max(rowPeak, engine.mix(
                        mono: source,
                        into: UnsafeMutableBufferPointer(start: destination[output], count: frames),
                        frameCount: frames
                    ))
                    state.channelEngines[channel][output] = engine
                }
            }
            state.peakMeter?.record(peak: rowPeak)
        }
    }

    private static func update(states: [MixInputState], mix: Mix, mutedSources: Set<SourceReference>, sourceLevels: [SourceLevel]) {
        let levels = Dictionary(uniqueKeysWithValues: sourceLevels.map { ($0.source, $0.level) })
        for (index, input) in mix.inputs.enumerated() where index < states.count {
            let state = states[index]
            let muted = input.isMuted || mutedSources.contains(input.source)
            let sourceLevel: Double = switch input.source {
            case .bus:
                1
            case .inputDevice, .application:
                levels[input.source] ?? 1
            }
            state.mainGain.store(Float(mix.level), ordering: .relaxed)
            for channel in state.channelGains.indices {
                let gain = channel < input.channelLevels.count ? input.channelLevels[channel] : 1
                state.channelGains[channel].value.store(Float(muted ? 0 : input.level * sourceLevel * gain), ordering: .relaxed)
                let selected = channel < input.channelRouting.count ? input.channelRouting[channel] : []
                for output in state.routing[channel].indices {
                    state.routing[channel][output].value.store(selected.contains(output + 1), ordering: .relaxed)
                }
            }
        }
    }

    private static func states(
        for mix: Mix,
        sampleRate: Double,
        meterTarget: String,
        meters: [String: RealtimePeakMeter],
        outputChannelCount: Int
    ) -> [MixInputState] {
        mix.inputs.map { input in
            let sourceKey = sourceKey(input.source)
            let peakMeter = meters["\(meterTarget)/\(sourceKey)"]
            let channels = max(max(input.channelRouting.count, input.channelLevels.count), 1)
            return MixInputState(
                sampleRate: sampleRate,
                sourceKey: sourceKey,
                peakMeter: peakMeter,
                channelCount: channels,
                outputChannelCount: outputChannelCount
            )
        }
    }

    static func sourceMeterKey(_ reference: SourceReference) -> String {
        switch reference {
        case let .inputDevice(uid): "input:\(uid.rawValue)"
        case let .application(id): "application:\(id.rawValue)"
        case let .bus(id): "bus:\(id.uuidString)"
        }
    }

    private static func sourceKey(_ reference: SourceReference) -> String {
        sourceMeterKey(reference)
    }
}

private func busDependencies(for mix: Mix, in buses: [UUID: VirtualBus]) -> Set<UUID> {
    var pending = mix.inputs.compactMap { input -> UUID? in
        guard case let .bus(id) = input.source else { return nil }
        return id
    }
    var relevant = Set<UUID>()
    while let id = pending.popLast() {
        guard relevant.insert(id).inserted, let bus = buses[id] else { continue }
        pending += bus.mix.inputs.compactMap { input -> UUID? in
            guard case let .bus(dependencyID) = input.source else { return nil }
            return dependencyID
        }
    }
    return relevant
}

private func nonBusSources(in mixes: [Mix]) -> Set<SourceReference> {
    Set(mixes.flatMap(\.inputs).map(\.source).filter {
        if case .bus = $0 {
            return false
        }
        return true
    })
}

private final class BusMuteState {
    let value: Atomic<Bool>

    init(_ muted: Bool) {
        value = Atomic(muted)
    }
}

private final class MixInputState {
    var channelEngines: [[StereoMixingEngine]]
    let sourceKey: String
    let peakMeter: RealtimePeakMeter?
    let mainGain = Atomic<Float>(1)
    let channelGains: [RealtimeGain]
    let routing: [[RealtimeRouting]]

    init(sampleRate: Double, sourceKey: String, peakMeter: RealtimePeakMeter?, channelCount: Int, outputChannelCount: Int) {
        channelEngines = (0 ..< channelCount).map { _ in
            (0 ..< outputChannelCount).map { _ in StereoMixingEngine(sampleRate: sampleRate, initialSourceGain: 0) }
        }
        self.sourceKey = sourceKey
        self.peakMeter = peakMeter
        channelGains = (0 ..< channelCount).map { _ in RealtimeGain(1) }
        routing = (0 ..< channelCount).map { _ in
            (0 ..< outputChannelCount).map { _ in RealtimeRouting(false) }
        }
    }
}

private final class RealtimeGain {
    let value: Atomic<Float>

    init(_ initialValue: Float) {
        value = Atomic(initialValue)
    }
}

private final class RealtimeRouting {
    let value: Atomic<Bool>

    init(_ initialValue: Bool) {
        value = Atomic(initialValue)
    }
}

private final class MultiChannelStorage {
    let channelCount: Int
    private let capacity: Int
    private let planes: [UnsafeMutablePointer<Float>]
    private let planePointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    var mutablePlanePointers: UnsafeBufferPointer<UnsafeMutablePointer<Float>> {
        UnsafeBufferPointer(start: planePointers, count: channelCount)
    }

    init(capacity: Int, channelCount: Int) {
        self.capacity = capacity
        self.channelCount = channelCount
        planes = (0 ..< channelCount).map { _ in
            let plane = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            plane.initialize(repeating: 0, count: capacity)
            return plane
        }
        planePointers = .allocate(capacity: channelCount)
        for channel in 0 ..< channelCount {
            planePointers.advanced(by: channel).initialize(to: planes[channel])
        }
    }

    deinit {
        for plane in planes {
            plane.deinitialize(count: capacity)
            plane.deallocate()
        }
        planePointers.deinitialize(count: channelCount)
        planePointers.deallocate()
    }

    func clear(frames: Int) {
        for plane in planes {
            plane.update(repeating: 0, count: frames)
        }
    }

    func readChannel(_ channel: Int, frames: Int) -> UnsafeBufferPointer<Float> {
        UnsafeBufferPointer(start: planes[min(max(channel, 0), channelCount - 1)], count: frames)
    }
}
