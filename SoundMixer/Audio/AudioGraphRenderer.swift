import Foundation

/// Renders one configured output from a validated graph. Source queues are drained
/// once per block, and each shared bus is rendered once in dependency order.
final class AudioGraphRenderer {
    private let outputMix: Mix
    private let busesByID: [UUID: VirtualBus]
    private let busOrder: [UUID]
    private let sourceRings: [String: RealtimeAudioRingBuffer]
    private let sourceBuffers: [String: AudioSourceStorage]
    private let busBuffers: [UUID: StereoStorage]
    private let sourceKeys: [String]
    private let mixStates: [UUID: [MixInputState]]
    private let outputState: [MixInputState]
    private let mutedSources: Set<SourceReference>
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
        mutedSources = Set(graph.configuration.mutedSources)
        busDestinationMeters = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map {
            ($0.id, meters["bus:\($0.id.uuidString)/destination"])
        }.compactMap { key, meter in meter.map { (key, $0) } })
        outputDestinationMeter = meters["\(targetKey)/destination"]
        busesByID = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { ($0.id, $0) })
        busOrder = graph.busRenderOrder
        self.sourceRings = sourceRings

        let mixes = graph.configuration.buses.map(\.mix) + [output.mix]
        let sources = Set(mixes.flatMap(\.inputs).compactMap { input -> String? in
            guard case .bus = input.source else { return Self.sourceKey(input.source) }
            return nil
        })
        sourceKeys = sources.sorted()
        sourceBuffers = Dictionary(uniqueKeysWithValues: sourceKeys.map { key in
            (key, AudioSourceStorage(capacity: Self.maximumFrames, channelCount: sourceRings[key]?.channelCount ?? 2))
        })
        busBuffers = Dictionary(uniqueKeysWithValues: busOrder.map { ($0, StereoStorage(capacity: Self.maximumFrames)) })
        mixStates = Dictionary(uniqueKeysWithValues: graph.configuration.buses.map { bus in
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
            busDestinationMeters[busID]?.record(
                left: storage.readLeftBuffer(frames), right: storage.readRightBuffer(frames), frameCount: frames
            )
        }

        renderMix(outputMix, states: outputState, into: (left, right), frames: frames)
        outputDestinationMeter?.record(left: UnsafeBufferPointer(left), right: UnsafeBufferPointer(right), frameCount: frames)
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
                renderPhysicalInput(input, state: state, mixLevel: mix.level, into: destination, frames: frames)
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
            state.engine.setSourceGain(Float(mutedSources.contains(input.source) ? 0 : input.level))
            state.engine.setMainGain(Float(mix.level))
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
        mixLevel: Double,
        into destination: (UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<Float>),
        frames: Int
    ) {
        guard let source = sourceBuffers[state.sourceKey] else { return }
        var rowPeak: Float = 0
        for channel in 0 ..< min(source.channelCount, state.channelEngines.count) {
            let routing = channel < input.channelRouting.count ? input.channelRouting[channel] : .ignore
            guard let placement = Self.placement(for: routing) else { continue }
            var engine = state.channelEngines[channel]
            let channelGain = channel < input.channelLevels.count ? input.channelLevels[channel] : 1
            engine.setSourceGain(Float(mutedSources.contains(input.source) ? 0 : input.level * channelGain))
            engine.setMainGain(Float(mixLevel))
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

private final class MixInputState {
    var engine: StereoMixingEngine
    var channelEngines: [StereoMixingEngine]
    let isMono: Bool
    let sourceKey: String
    let peakMeter: RealtimePeakMeter?

    init(sampleRate: Double, isMono: Bool, sourceKey: String, peakMeter: RealtimePeakMeter?, channelCount: Int) {
        engine = StereoMixingEngine(sampleRate: sampleRate)
        channelEngines = (0 ..< channelCount).map { _ in StereoMixingEngine(sampleRate: sampleRate) }
        self.isMono = isMono
        self.sourceKey = sourceKey
        self.peakMeter = peakMeter
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
