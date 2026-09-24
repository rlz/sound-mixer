import AudioToolbox
import CoreAudio
import Foundation

/// Applies a validated graph to capture and output resources. Queue snapshots are
/// replaced only after capture has stopped, so each ring keeps one producer.
final class AudioRoutingCoordinator {
    var onRouteError: ((String, String) -> Void)?

    private let capture: AudioCaptureCoordinator
    private let output = CoreAudioOutputCoordinator()
    private var fanout: AudioSourceFanout?
    private var renderers: [String: AudioGraphRenderer] = [:]
    private var ringsByRoute: [String: [String: RealtimeAudioRingBuffer]] = [:]
    private var sourceMeters: [String: RealtimePeakMeter] = [:]
    private var renderMeters: [String: RealtimePeakMeter] = [:]
    private var lastGraph: MixGraphSnapshot?
    private var lastDevices: [AudioDeviceSnapshot] = []
    private var lastProcesses: [AudioProcessSnapshot] = []
    private var lastEnabled: Bool?

    init(capture: AudioCaptureCoordinator) {
        self.capture = capture
        capture.onAudio = { [weak self] id, buffers, frames, format in
            self?.fanout?.consume(id: id, buffers: buffers, frames: frames, format: format)
        }
    }

    @discardableResult
    func update(graph: MixGraphSnapshot, devices: [AudioDeviceSnapshot], processes: [AudioProcessSnapshot]) -> Bool {
        let orderedDevices = devices.sorted { $0.uid < $1.uid }
        let orderedProcesses = processes.sorted {
            $0.applicationID == $1.applicationID ? $0.processID < $1.processID : $0.applicationID < $1.applicationID
        }
        let enabled = graph.configuration.isEnabled
        guard needsUpdate(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled) else { return false }
        remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
        stopCurrentRouting()
        guard enabled else { return true }

        let deviceByUID = Dictionary(orderedDevices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let processByID = Dictionary(orderedProcesses.map { ($0.applicationID, $0) }, uniquingKeysWith: { first, _ in first })
        var queuesBySource: [String: [RealtimeAudioRingBuffer]] = [:]
        var captureSources = Set<String>()
        renderMeters = Dictionary(uniqueKeysWithValues: Self.renderMeterKeys(graph.configuration).map { ($0, RealtimePeakMeter()) })
        for device in orderedDevices where device.inputChannels > 0 {
            let key = "input:\(device.uid)"
            queuesBySource[key] = []
            captureSources.insert(key)
        }
        startOutputRoutes(graph: graph, devices: deviceByUID, queues: &queuesBySource, sources: &captureSources)
        for route in graph.configuration.blackHoleRoutes {
            let key = "route:\(route.id.uuidString)"
            queuesBySource[key] = queuesBySource[key] ?? []
            captureSources.insert(key)
        }
        let inputChannelCounts = Dictionary(uniqueKeysWithValues: deviceByUID.values.map {
            ("input:\($0.uid)", min(max($0.inputChannels, 1), 64))
        }).merging(Dictionary(uniqueKeysWithValues: graph.configuration.blackHoleRoutes.map {
            ("route:\($0.id.uuidString)", 2)
        }), uniquingKeysWith: { first, _ in first })
        fanout = AudioSourceFanout(queuesBySource: queuesBySource, inputChannelCounts: inputChannelCounts)
        sourceMeters = fanout?.metersBySource ?? [:]
        startCapture(sources: captureSources, graph: graph, devices: deviceByUID, processes: processByID)
        return true
    }

    func stop() {
        capture.stopAll()
        output.stopAll()
        renderers.removeAll()
        ringsByRoute.removeAll()
        sourceMeters.removeAll()
        renderMeters.removeAll()
        fanout = nil
        lastEnabled = false
    }

    private func needsUpdate(
        graph: MixGraphSnapshot,
        devices: [AudioDeviceSnapshot],
        processes: [AudioProcessSnapshot],
        enabled: Bool
    ) -> Bool {
        lastGraph != graph || lastDevices != devices || lastProcesses != processes || lastEnabled != enabled
    }

    private func remember(
        graph: MixGraphSnapshot,
        devices: [AudioDeviceSnapshot],
        processes: [AudioProcessSnapshot],
        enabled: Bool
    ) {
        lastGraph = graph
        lastDevices = devices
        lastProcesses = processes
        lastEnabled = enabled
    }

    private func stopCurrentRouting() {
        capture.stopAll()
        output.stopAll()
        renderers.removeAll()
        ringsByRoute.removeAll()
        sourceMeters.removeAll()
        renderMeters.removeAll()
        fanout = nil
    }

    private func startOutputRoutes(
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        queues: inout [String: [RealtimeAudioRingBuffer]],
        sources: inout Set<String>
    ) {
        for route in makeRoutes(graph.configuration) {
            guard let rings = startOutputRoute(route, graph: graph, devices: devices) else { continue }
            ringsByRoute[route.key] = rings
            for (key, ring) in rings {
                queues[key, default: []].append(ring)
                sources.insert(key)
            }
        }
    }

    private func startOutputRoute(
        _ route: RenderRoute,
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot]
    ) -> [String: RealtimeAudioRingBuffer]? {
        guard let device = devices[route.uid], device.isAlive,
              route.channels.max().map({ device.outputChannels > $0 }) ?? false,
              device.nominalSampleRate.isFinite, device.nominalSampleRate > 0
        else {
            onRouteError?(route.key, "The selected output device or channels are unavailable.")
            return nil
        }

        let sourceKeys = Self.sourceKeys(in: route.mix, buses: graph.configuration.buses)
        let rings = Dictionary(uniqueKeysWithValues: sourceKeys.map { key in
            let channelCount: Int
            if key.hasPrefix("input:") {
                let uid = String(key.dropFirst("input:".count))
                channelCount = min(max(devices[uid]?.inputChannels ?? 2, 1), 64)
            } else {
                channelCount = 2
            }
            return (key, RealtimeAudioRingBuffer(channelCount: channelCount))
        })
        let renderer = AudioGraphRenderer(
            graph: graph,
            output: OutputMix(deviceUID: DeviceUID(rawValue: route.uid), mix: route.mix),
            sourceRings: rings,
            monoSourceKeys: [],
            targetKey: route.targetKey,
            meters: renderMeters
        )
        do {
            try output.start(
                route: CoreAudioOutputCoordinator.Route(
                    key: route.key,
                    deviceID: device.deviceID,
                    deviceChannelCount: device.outputChannels,
                    selectedChannels: route.channels,
                    sampleRate: 48000
                ),
                render: { left, right, frames in renderer.render(left: left, right: right, frameCount: frames) }
            )
            renderers[route.key] = renderer
            return rings
        } catch {
            onRouteError?(route.key, error.localizedDescription)
            return nil
        }
    }

    private func startCapture(
        sources: Set<String>,
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        processes: [String: AudioProcessSnapshot]
    ) {
        for source in sources {
            if source.hasPrefix("input:") {
                startInput(source: source, devices: devices)
            } else if source.hasPrefix("route:") {
                startBlackHoleRoute(source: source, routes: graph.configuration.blackHoleRoutes, devices: devices)
            } else if source.hasPrefix("application:") {
                startApplication(source: source, processes: processes)
            }
        }
    }

    private func startBlackHoleRoute(source: String, routes: [BlackHoleRoute], devices: [String: AudioDeviceSnapshot]) {
        let id = String(source.dropFirst("route:".count))
        guard let uuid = UUID(uuidString: id),
              let route = routes.first(where: { $0.id == uuid }),
              let device = devices[route.deviceUID.rawValue], device.isAlive,
              let channels = Self.selectedInputChannels(route.channels),
              device.inputChannels > (channels.max() ?? Int.max)
        else {
            let reason = "The assigned BlackHole input channel pair is unavailable."
            capture.reportUnavailable(id: source, reason: reason)
            onRouteError?(source, reason)
            return
        }
        capture.startBlackHoleRoute(id: id, deviceID: device.deviceID, channels: channels)
    }

    private static func selectedInputChannels(_ channels: BlackHoleChannels) -> [Int]? {
        guard case let .stereo(left, right) = channels else { return nil }
        return [left - 1, right - 1]
    }

    private func startInput(source: String, devices: [String: AudioDeviceSnapshot]) {
        let uid = String(source.dropFirst("input:".count))
        guard let device = devices[uid], device.isAlive, device.inputChannels > 0 else { return }
        capture.startInput(uid: uid, deviceID: device.deviceID)
    }

    private func startApplication(source: String, processes: [String: AudioProcessSnapshot]) {
        let appID = String(source.dropFirst("application:".count))
        guard let process = processes[appID], process.isProducingOutput else { return }
        capture.startApplication(id: appID, processID: process.processID)
    }

    func diagnostics() -> [String: AudioQueueDiagnostics] {
        var result: [String: AudioQueueDiagnostics] = [:]
        for (route, rings) in ringsByRoute {
            for (source, ring) in rings {
                result["\(route)/\(source)"] = AudioQueueDiagnostics(
                    droppedFrames: ring.droppedFrames,
                    underrunFrames: ring.underrunFrames
                )
            }
        }
        return result
    }

    func sourceLevelReadings() -> [String: Double] {
        sourceMeters.compactMapValues { $0.reading() }
    }

    func inputChannelLevelReadings() -> [String: [Double?]] {
        fanout?.channelReadingsBySource ?? [:]
    }

    func renderLevelReadings() -> [String: Double] {
        renderMeters.compactMapValues { $0.reading() }
    }
}

extension AudioRoutingCoordinator {
    private static func renderMeterKeys(_ configuration: MixerConfiguration) -> [String] {
        var keys: [String] = []
        for output in configuration.outputMixes {
            let target = "output:\(output.deviceUID.rawValue)"
            keys.append("\(target)/destination")
            keys += output.mix.inputs.map { "\(target)/\(AudioGraphRenderer.sourceMeterKey($0.source))" }
        }
        for route in configuration.blackHoleRoutes {
            let target = "route:\(route.id.uuidString)"
            keys.append("\(target)/destination")
            keys += route.mix.inputs.map { "\(target)/\(AudioGraphRenderer.sourceMeterKey($0.source))" }
        }
        for bus in configuration.buses {
            let target = "bus:\(bus.id.uuidString)"
            keys.append("\(target)/destination")
            keys += bus.mix.inputs.map { "\(target)/\(AudioGraphRenderer.sourceMeterKey($0.source))" }
        }
        return keys
    }

    private func makeRoutes(_ configuration: MixerConfiguration) -> [RenderRoute] {
        var routes = configuration.outputMixes.map { output in
            RenderRoute(
                key: "output:\(output.deviceUID.rawValue)",
                uid: output.deviceUID.rawValue,
                channels: [0, 1],
                mix: output.mix,
                targetKey: "output:\(output.deviceUID.rawValue)"
            )
        }
        routes += configuration.blackHoleRoutes.map { route in
            let channels: [Int] = switch route.channels {
            case let .mono(channel): [channel - 1]
            case let .stereo(left, right): [left - 1, right - 1]
            }
            return RenderRoute(
                key: "blackhole:\(route.id.uuidString)",
                uid: route.deviceUID.rawValue,
                channels: channels,
                mix: route.mix,
                targetKey: "route:\(route.id.uuidString)"
            )
        }
        return routes
    }

    private static func sourceKeys(in mix: Mix, buses: [VirtualBus]) -> [String] {
        var keys = Set<String>()
        let busesByID = Dictionary(uniqueKeysWithValues: buses.map { ($0.id, $0) })
        var pending = [mix]
        var visitedBuses = Set<UUID>()
        while let current = pending.popLast() {
            for input in current.inputs {
                switch input.source {
                case let .inputDevice(uid): keys.insert("input:\(uid.rawValue)")
                case let .application(id): keys.insert("application:\(id.rawValue)")
                case let .bus(id):
                    if visitedBuses.insert(id).inserted, let bus = busesByID[id] {
                        pending.append(bus.mix)
                    }
                case let .blackHoleRoute(id):
                    keys.insert("route:\(id.uuidString)")
                }
            }
        }
        return keys.sorted()
    }
}

private struct RenderRoute {
    let key: String
    let uid: String
    let channels: [Int]
    let mix: Mix
    let targetKey: String
}
