import Foundation

/// Renders one configured output from a validated graph. Source queues are drained
/// once per block, and each shared bus is rendered once in dependency order.
final class AudioGraphRenderer {
    private let outputMix: Mix
    private let busesByID: [UUID: VirtualBus]
    private let busOrder: [UUID]
    private let sourceRings: [String: RealtimeStereoRingBuffer]
    private let sourceBuffers: [String: StereoStorage]
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
        sourceRings: [String: RealtimeStereoRingBuffer],
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
        sourceBuffers = Dictionary(uniqueKeysWithValues: sourceKeys.map { ($0, StereoStorage(capacity: Self.maximumFrames)) })
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
            _ = sourceRings[key]?.read(into: storage.leftBuffer(frames), storage.rightBuffer(frames), frameCount: frames)
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
            let source: StereoStorage? = switch input.source {
            case let .bus(id): busBuffers[id]
            case .inputDevice, .application, .blackHoleRoute:
                sourceBuffers[state.sourceKey]
            }
            guard let source else { continue }
            state.engine.setSourceGain(Float(mutedSources.contains(input.source) ? 0 : input.level))
            state.engine.setMainGain(Float(mix.level))
            if state.isMono {
                state.engine.mix(
                    mono: source.readLeftBuffer(frames), placement: input.monoPlacement,
                    into: destination.0, outputRight: destination.1, frameCount: frames,
                    peakMeter: state.peakMeter
                )
            } else {
                state.engine.mix(
                    left: source.readLeftBuffer(frames), right: source.readRightBuffer(frames),
                    into: destination.0, outputRight: destination.1, frameCount: frames,
                    peakMeter: state.peakMeter
                )
            }
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
            return MixInputState(sampleRate: sampleRate, isMono: isMono, sourceKey: sourceKey, peakMeter: peakMeter)
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
    let isMono: Bool
    let sourceKey: String
    let peakMeter: RealtimePeakMeter?

    init(sampleRate: Double, isMono: Bool, sourceKey: String, peakMeter: RealtimePeakMeter?) {
        engine = StereoMixingEngine(sampleRate: sampleRate)
        self.isMono = isMono
        self.sourceKey = sourceKey
        self.peakMeter = peakMeter
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
