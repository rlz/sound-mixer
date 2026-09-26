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
    private let sourceBuffers: [String: AudioSourceStorage]
    private let sourceReferences: Set<SourceReference>
    private let busBuffers: [UUID: StereoStorage]
    private let sourceKeys: [String]
    private let mixStates: [UUID: [MixInputState]]
    private let outputState: [MixInputState]
    private let mutedSources: Set<SourceReference>
    private let busMuteStates: [UUID: BusMuteState]
    private let busDestinationMeters: [UUID: RealtimePeakMeter]
    private let outputDestinationMeter: RealtimePeakMeter?
    private static let maximumFrames = 8192

    init(
        graph: MixGraphSnapshot,
        output: OutputMix,
        sourceRings: [String: RealtimeAudioRingBuffer],
        monoSourceKeys: Set<String> = [],
        targetKey: String,
        meters: [String: RealtimePeakMeter]
    ) {
        outputMix = output.mix
        self.targetKey = targetKey
        mutedSources = Set(graph.configuration.mutedSources)
        let allBusesByID = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { ($0.id, $0) })
        var pendingBusIDs = output.mix.inputs.compactMap { input -> UUID? in
            guard case let .bus(id) = input.source else { return nil }
            return id
        }
        var relevantBusIDs = Set<UUID>()
        while let id = pendingBusIDs.popLast() {
            guard relevantBusIDs.insert(id).inserted, let bus = allBusesByID[id] else { continue }
            pendingBusIDs += bus.mix.inputs.compactMap { input -> UUID? in
                guard case let .bus(dependencyID) = input.source else { return nil }
                return dependencyID
            }
        }
        let relevantBuses = graph.configuration.buses.filter { relevantBusIDs.contains($0.id) }
        let relevantBusOrder = graph.busRenderOrder.filter { relevantBusIDs.contains($0) }
        busMuteStates = Dictionary(uniqueKeysWithValues: relevantBuses.map {
            ($0.id, BusMuteState(Set(graph.configuration.mutedBuses).contains($0.id)))
        })
        busDestinationMeters = Dictionary(uniqueKeysWithValues: relevantBuses.map {
            ($0.id, meters["bus:\($0.id.uuidString)/destination"])
        }.compactMap { key, meter in meter.map { (key, $0) } })
        outputDestinationMeter = meters["\(targetKey)/destination"]
        busesByID = Dictionary(uniqueKeysWithValues: relevantBuses.map { ($0.id, $0) })
        busOrder = relevantBusOrder
        self.sourceRings = sourceRings

        let mixes = relevantBuses.map(\.mix) + [output.mix]
        sourceReferences = Set(mixes.flatMap(\.inputs).map(\.source).filter {
            if case .bus = $0 {
                return false
            }
            return true
        })
        let sources = Set(mixes.flatMap(\.inputs).compactMap { input -> String? in
            guard case .bus = input.source else { return Self.sourceKey(input.source) }
            return nil
        })
        sourceKeys = sources.sorted()
        sourceBuffers = Dictionary(uniqueKeysWithValues: sourceKeys.map { key in
            (key, AudioSourceStorage(capacity: Self.maximumFrames, channelCount: sourceRings[key]?.channelCount ?? 2))
        })
        busBuffers = Dictionary(uniqueKeysWithValues: busOrder.map { ($0, StereoStorage(capacity: Self.maximumFrames)) })
        mixStates = Dictionary(uniqueKeysWithValues: relevantBuses.map { bus in
            (
                bus.id,
                Self.states(
                    for: bus.mix, sampleRate: 48000, monoSourceKeys: monoSourceKeys,
                    meterTarget: "bus:\(bus.id.uuidString)", meters: meters
                )
            )
        })
        outputState = Self.states(
            for: output.mix, sampleRate: 48000, monoSourceKeys: monoSourceKeys,
            meterTarget: targetKey, meters: meters
        )
    }

    func render(
        left: UnsafeMutableBufferPointer<Float>,
        right: UnsafeMutableBufferPointer<Float>,
        frameCount: Int
    ) {
        let frames = min(frameCount, min(Self.maximumFrames, min(left.count, right.count)))
        guard frames > 0 else { return }
        left.update(repeating: 0)
        right.update(repeating: 0)

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
                left: storage.readLeftBuffer(frames), right: storage.readRightBuffer(frames), frameCount: frames
            )
        }

        renderMix(outputMix, states: outputState, into: (left, right), frames: frames)
        outputDestinationMeter?.record(left: UnsafeBufferPointer(left), right: UnsafeBufferPointer(right), frameCount: frames)
    }

    /// Publishes gain changes to the render thread without rebuilding its audio graph.
    func updateGains(from graph: MixGraphSnapshot) {
        let mutedBusIDs = Set(graph.configuration.mutedBuses)
        for (id, state) in busMuteStates {
            state.value.store(mutedBusIDs.contains(id), ordering: .relaxed)
        }
        let busMixes = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { ($0.id, $0.mix) })
        for (id, states) in mixStates {
            guard let mix = busMixes[id] else { continue }
            Self.update(states: states, mix: mix, mutedSources: Set(graph.configuration.mutedSources), sourceLevels: graph.configuration.sourceLevels)
        }
        let mix: Mix? = if targetKey.hasPrefix("output:") {
            graph.configuration.outputMixes.first(where: { targetKey == "output:\($0.deviceUID.rawValue)" })?.mix
        } else {
            graph.configuration.blackHoleRoutes.first(where: { targetKey == "route:\($0.id.uuidString)" })?.mix
        }
        if let mix {
            Self.update(states: outputState, mix: mix, mutedSources: Set(graph.configuration.mutedSources), sourceLevels: graph.configuration.sourceLevels)
        }
    }

    func depends(on changedSources: Set<SourceReference>, changedBuses: Set<UUID>) -> Bool {
        !sourceReferences.isDisjoint(with: changedSources) ||
            !Set(busMuteStates.keys).isDisjoint(with: changedBuses)
    }

    private func renderMix(
        _ mix: Mix,
        states: [MixInputState],
        into destination: StereoStorage,
        frames: Int
    ) {
        let output = (destination.leftBuffer(frames), destination.rightBuffer(frames))
        renderMix(mix, states: states, into: output, frames: frames)
    }

    private func renderMix(
        _ mix: Mix,
        states: [MixInputState],
        into destination: (UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<Float>),
        frames: Int
    ) {
        for (index, input) in mix.inputs.enumerated() where index < states.count {
            let state = states[index]
            if case .inputDevice = input.source {
                renderPhysicalInput(input, state: state, into: destination, frames: frames)
                continue
            }
            let sourceLeft: UnsafeBufferPointer<Float>
            let sourceRight: UnsafeBufferPointer<Float>
            switch input.source {
            case let .bus(id):
                guard let busStorage = busBuffers[id] else { continue }
                sourceLeft = busStorage.readLeftBuffer(frames)
                sourceRight = busStorage.readRightBuffer(frames)
            case .application, .blackHoleRoute:
                guard let multichannel = sourceBuffers[state.sourceKey] else { continue }
                sourceLeft = multichannel.readChannel(0, frames: frames)
                sourceRight = multichannel.readChannel(min(1, multichannel.channelCount - 1), frames: frames)
            case .inputDevice:
                continue
            }
            state.engine.setSourceGain(state.sourceGain.load(ordering: .relaxed))
            state.engine.setMainGain(state.mainGain.load(ordering: .relaxed))
            if state.isMono {
                _ = state.engine.mix(
                    mono: sourceLeft, placement: input.monoPlacement,
                    into: destination.0, outputRight: destination.1, frameCount: frames,
                    peakMeter: state.peakMeter
                )
            } else {
                state.engine.mix(
                    left: sourceLeft, right: sourceRight,
                    into: destination.0, outputRight: destination.1, frameCount: frames,
                    peakMeter: state.peakMeter
                )
            }
        }
    }

    private func renderPhysicalInput(
        _ input: MixInput,
        state: MixInputState,
        into destination: (UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<Float>),
        frames: Int
    ) {
        guard let source = sourceBuffers[state.sourceKey] else { return }
        var rowPeak: Float = 0
        for channel in 0 ..< min(source.channelCount, state.channelEngines.count) {
            let routing = channel < input.channelRouting.count ? input.channelRouting[channel] : .ignore
            guard let placement = Self.placement(for: routing) else { continue }
            var engine = state.channelEngines[channel]
            let channelGain = channel < state.channelGains.count ? state.channelGains[channel].value.load(ordering: .relaxed) : 1
            engine.setSourceGain(channelGain)
            engine.setMainGain(state.mainGain.load(ordering: .relaxed))
            rowPeak = max(
                rowPeak,
                engine.mix(
                    mono: source.readChannel(channel, frames: frames), placement: placement,
                    into: destination.0, outputRight: destination.1, frameCount: frames
                )
            )
            state.channelEngines[channel] = engine
        }
        state.peakMeter?.record(peak: rowPeak)
    }

    private static func update(states: [MixInputState], mix: Mix, mutedSources: Set<SourceReference>, sourceLevels: [SourceLevel]) {
        let levels = Dictionary(uniqueKeysWithValues: sourceLevels.map { ($0.source, $0.level) })
        for (index, input) in mix.inputs.enumerated() where index < states.count {
            let state = states[index]
            let muted = mutedSources.contains(input.source)
            let sourceLevel: Double = switch input.source {
            case .bus, .blackHoleRoute:
                1
            case .inputDevice, .application:
                levels[input.source] ?? 1
            }
            state.sourceGain.store(Float(muted ? 0 : input.level * sourceLevel), ordering: .relaxed)
            state.mainGain.store(Float(mix.level), ordering: .relaxed)
            for channel in state.channelGains.indices {
                let gain = channel < input.channelLevels.count ? input.channelLevels[channel] : 1
                state.channelGains[channel].value.store(Float(muted ? 0 : input.level * sourceLevel * gain), ordering: .relaxed)
            }
        }
    }

    private static func placement(for routing: ChannelRouting) -> MonoPlacement? {
        switch routing {
        case .ignore: nil
        case .first: .left
        case .second: .right
        case .both: .both
        }
    }

    private static func states(
        for mix: Mix,
        sampleRate: Double,
        monoSourceKeys: Set<String>,
        meterTarget: String,
        meters: [String: RealtimePeakMeter]
    ) -> [MixInputState] {
        mix.inputs.map { input in
            let isMono: Bool = switch input.source {
            case .bus, .blackHoleRoute: false
            case .inputDevice, .application: monoSourceKeys.contains(sourceKey(input.source))
            }
            let sourceKey = sourceKey(input.source)
            let peakMeter = meters["\(meterTarget)/\(sourceKey)"]
            let channels = max(max(input.channelRouting.count, input.channelLevels.count), 1)
            return MixInputState(
                sampleRate: sampleRate,
                isMono: isMono,
                sourceKey: sourceKey,
                peakMeter: peakMeter,
                channelCount: channels
            )
        }
    }

    static func sourceMeterKey(_ reference: SourceReference) -> String {
        switch reference {
        case let .inputDevice(uid): "input:\(uid.rawValue)"
        case let .application(id): "application:\(id.rawValue)"
        case let .bus(id): "bus:\(id.uuidString)"
        case let .blackHoleRoute(id): "route:\(id.uuidString)"
        }
    }

    private static func sourceKey(_ reference: SourceReference) -> String {
        sourceMeterKey(reference)
    }
}

private final class BusMuteState {
    let value: Atomic<Bool>

    init(_ muted: Bool) {
        value = Atomic(muted)
    }
}

private final class MixInputState {
    var engine: StereoMixingEngine
    var channelEngines: [StereoMixingEngine]
    let isMono: Bool
    let sourceKey: String
    let peakMeter: RealtimePeakMeter?
    let sourceGain = Atomic<Float>(1)
    let mainGain = Atomic<Float>(1)
    let channelGains: [RealtimeGain]

    init(sampleRate: Double, isMono: Bool, sourceKey: String, peakMeter: RealtimePeakMeter?, channelCount: Int) {
        engine = StereoMixingEngine(sampleRate: sampleRate)
        channelEngines = (0 ..< channelCount).map { _ in StereoMixingEngine(sampleRate: sampleRate) }
        self.isMono = isMono
        self.sourceKey = sourceKey
        self.peakMeter = peakMeter
        channelGains = (0 ..< channelCount).map { _ in RealtimeGain(1) }
    }
}

private final class RealtimeGain {
    let value: Atomic<Float>

    init(_ initialValue: Float) {
        value = Atomic(initialValue)
    }
}

private final class AudioSourceStorage {
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

private final class StereoStorage {
    let capacity: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    init(capacity: Int) {
        self.capacity = capacity
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        left.deinitialize(count: capacity)
        right.deinitialize(count: capacity)
        left.deallocate()
        right.deallocate()
    }

    func clear(frames: Int) {
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
    }

    func leftBuffer(_ frames: Int) -> UnsafeMutableBufferPointer<Float> {
        UnsafeMutableBufferPointer(start: left, count: frames)
    }

    func rightBuffer(_ frames: Int) -> UnsafeMutableBufferPointer<Float> {
        UnsafeMutableBufferPointer(start: right, count: frames)
    }

    func readLeftBuffer(_ frames: Int) -> UnsafeBufferPointer<Float> {
        UnsafeBufferPointer(start: left, count: frames)
    }

    func readRightBuffer(_ frames: Int) -> UnsafeBufferPointer<Float> {
        UnsafeBufferPointer(start: right, count: frames)
    }
}
