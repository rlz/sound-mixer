import AudioToolbox
import CoreAudio
import Foundation

// Applies a validated graph by replacing only changed source and endpoint resources.
// Routing lifecycle and callback ownership are intentionally kept in one coordinator.
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
final class AudioRoutingCoordinator {
    var onRouteError: ((String, String) -> Void)?
    var onRoutingReset: (() -> Void)?

    private let capture: AudioCaptureCoordinator
    private let output = CoreAudioOutputCoordinator()
    private let fanout = RealtimePublication<AudioSourceFanout>()
    private var renderers: [String: AudioGraphRenderer] = [:]
    private var activeRouteKeys = Set<String>()
    private var busMeterPumps: [UUID: BusMeterPump] = [:]
    private var ringsByBusMeter: [UUID: [String: RealtimeAudioRingBuffer]] = [:]
    private var busMeterSignatures: [UUID: BusMeterSignature] = [:]
    private var ringsByRoute: [String: [String: RealtimeAudioRingBuffer]] = [:]
    private var sourceMeters: [String: RealtimePeakMeter] = [:]
    private var renderMeters: [String: RealtimePeakMeter] = [:]
    private var deviceMeters: [String: RealtimePeakMeter] = [:]
    private var deviceMeterDevices: [String: AudioDeviceSnapshot] = [:]
    private var lastGraph: MixGraphSnapshot?
    private var lastDevices: [AudioDeviceSnapshot] = []
    private var lastProcesses: [AudioProcessSnapshot] = []
    private var lastEnabled: Bool?

    init(capture: AudioCaptureCoordinator) {
        self.capture = capture
        capture.onAudio = { [weak self] id, buffers, frames, format in
            guard let self else { return }
            let current = fanout.beginRead()
            defer { fanout.endRead() }
            current?.consume(id: id, buffers: buffers, frames: frames, format: format)
        }
    }

    @discardableResult
    // The transition stages share prepared route and capture state.
    // swiftlint:disable cyclomatic_complexity function_body_length
    func update(graph: MixGraphSnapshot, devices: [AudioDeviceSnapshot], processes: [AudioProcessSnapshot]) -> Bool {
        let orderedDevices = devices.sorted { $0.uid < $1.uid }
        let applicationKeys = Set(makeRoutes(graph.configuration, devices: orderedDevices).flatMap {
            Self.sourceKeys(in: $0.mix, buses: graph.configuration.buses).filter { $0.hasPrefix("application:") }
        }).union(graph.configuration.applications.map { "application:\($0.rawValue)" })
        let orderedProcesses = processes.filter { applicationKeys.contains("application:\($0.applicationID)") }.sorted {
            if $0.applicationID != $1.applicationID {
                return $0.applicationID < $1.applicationID
            }
            if $0.isProducingOutput != $1.isProducingOutput {
                return $0.isProducingOutput
            }
            return $0.processID < $1.processID
        }
        let enabled = graph.configuration.isEnabled
        let hiddenDeviceUIDs = Set(graph.configuration.hiddenDeviceUIDs.map(\.rawValue))
        let deviceRoutingChanged = lastDevices.count != orderedDevices.count ||
            !zip(lastDevices, orderedDevices).allSatisfy { $0.hasSameRouting(as: $1) }
        guard needsUpdate(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled) else { return false }
        if let lastGraph, enabled,
           !deviceRoutingChanged,
           Self.hasSameProcessRouting(lastProcesses, orderedProcesses),
           Self.hasOnlyRoutingChanges(from: lastGraph.configuration, to: graph.configuration)
        {
            for renderer in renderers.values {
                renderer.updateRouting(from: graph, previous: lastGraph)
            }
            for pump in busMeterPumps.values {
                pump.renderer.updateRouting(from: graph, previous: lastGraph)
            }
            remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
            return false
        }
        if let lastGraph, enabled, Self.hasOnlyGainChanges(from: lastGraph.configuration, to: graph.configuration),
           !deviceRoutingChanged,
           Self.hasSameProcessRouting(lastProcesses, orderedProcesses)
        {
            // Gain-only edits do not rebuild routing. Republish the small gain
            // snapshot to every renderer so global source gains reach all
            // routes, including virtual and chained bus renderers.
            republishGains(from: graph)
            remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
            return false
        }
        if let lastGraph, enabled,
           !deviceRoutingChanged,
           Self.hasSameProcessRouting(lastProcesses, orderedProcesses),
           RuntimeGraphShape.hasOnlyEmptyBusChanges(from: lastGraph.configuration, to: graph.configuration)
        {
            retainRenderMeters(for: graph.configuration)
            remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
            return true
        }
        if !enabled {
            onRoutingReset?()
            remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
            stopCurrentRouting()
            return true
        }

        let deviceByUID = Dictionary(orderedDevices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let processByID = Dictionary(orderedProcesses.map { ($0.applicationID, $0) }, uniquingKeysWith: { first, _ in first })

        let routes = makeRoutes(graph.configuration, devices: orderedDevices)
        let desiredRoutes = Dictionary(routes.map { ($0.key, $0) }, uniquingKeysWith: { _, latest in latest })
        let previousConfiguration = lastGraph?.configuration
        let desiredShape = RuntimeGraphShape(configuration: graph.configuration)
        let changedShapes = lastGraph.map {
            desiredShape.changedRouteKeys(from: RuntimeGraphShape(configuration: $0.configuration))
        } ?? Set(desiredRoutes.keys)
        let changedMutedSources = Set(previousConfiguration?.mutedSources ?? [])
            .symmetricDifference(graph.configuration.mutedSources)
            .union(Set(previousConfiguration?.hiddenDeviceUIDs ?? [])
                .symmetricDifference(graph.configuration.hiddenDeviceUIDs)
                .map(SourceReference.inputDevice))
        let changedMutedBuses = Set(previousConfiguration?.mutedBuses ?? [])
            .symmetricDifference(graph.configuration.mutedBuses)
        let changedRouteKeys = Set(desiredRoutes.compactMap { key, route in
            guard !changedShapes.contains(key), activeRouteKeys.contains(key),
                  renderers[key] != nil,
                  let routeRings = ringsByRoute[key],
                  routeRingsMatch(routeRings, route: route, devices: deviceByUID, buses: graph.configuration.buses),
                  let oldDevice = lastDevices.first(where: { $0.uid == route.uid }),
                  let newDevice = deviceByUID[route.uid], oldDevice.hasSameOutputRouting(as: newDevice)
            else { return key }
            return nil
        })
        let removedRouteKeys = Set(ringsByRoute.keys).subtracting(desiredRoutes.keys)
        let routeWork = changedRouteKeys.union(removedRouteKeys)
        if !routeWork.isEmpty {
            onRoutingReset?()
        }

        var retiringRings: [(String, RealtimeAudioRingBuffer)] = []
        var previousRingsByChangedRoute: [String: [String: RealtimeAudioRingBuffer]] = [:]
        for key in routeWork {
            if removedRouteKeys.contains(key) ||
                desiredRoutes[key].flatMap({ deviceByUID[$0.uid] })?.isAlive != true
            {
                output.stop(key: key)
            }
            activeRouteKeys.remove(key)
            renderers.removeValue(forKey: key)
            if let oldRings = ringsByRoute.removeValue(forKey: key), !removedRouteKeys.contains(key) {
                previousRingsByChangedRoute[key] = oldRings
            }
        }

        var queuesBySource: [String: [RealtimeAudioRingBuffer]] = [:]
        var captureSources = Set<String>()
        retainRenderMeters(for: graph.configuration)
        for device in orderedDevices where device.inputChannels > 0 && !hiddenDeviceUIDs.contains(device.uid) {
            let key = "input:\(device.uid)"
            queuesBySource[key] = []
            captureSources.insert(key)
        }
        for route in routes {
            let routeRings: [String: RealtimeAudioRingBuffer]?
            if routeWork.contains(route.key) {
                let previousRings = previousRingsByChangedRoute[route.key] ?? [:]
                routeRings = startOutputRoute(
                    route, graph: graph, devices: deviceByUID, existingRings: previousRings
                )
                for (source, oldRing) in previousRings where routeRings?[source] !== oldRing {
                    retiringRings.append((source, oldRing))
                }
                ringsByRoute[route.key] = routeRings
            } else {
                routeRings = ringsByRoute[route.key]
                if renderers[route.key]?.depends(on: changedMutedSources, changedBuses: changedMutedBuses) == true {
                    renderers[route.key]?.updateGains(from: graph)
                }
            }
            for (source, ring) in routeRings ?? [:] {
                queuesBySource[source, default: []].append(ring)
                captureSources.insert(source)
            }
        }
        reconcileBusMeters(
            graph: graph, shape: desiredShape, devices: deviceByUID,
            changedMutedSources: changedMutedSources, changedMutedBuses: changedMutedBuses,
            queues: &queuesBySource, sources: &captureSources
        )
        for id in graph.configuration.applications {
            let key = "application:\(id.rawValue)"
            queuesBySource[key] = queuesBySource[key] ?? []
            captureSources.insert(key)
        }
        let inputChannelCounts = Dictionary(uniqueKeysWithValues: deviceByUID.values.map {
            ("input:\($0.uid)", min(max($0.inputChannels, 1), 64))
        })
        let fanoutChanged = !hasSameFanoutTopology(
            queuesBySource: queuesBySource,
            inputChannelCounts: inputChannelCounts
        )
        var nextFanout: AudioSourceFanout?
        if fanoutChanged {
            let prepared = makeFanoutSnapshot(queuesBySource: queuesBySource, inputChannelCounts: inputChannelCounts)
            nextFanout = prepared
            sourceMeters = prepared.metersBySource
            if !retiringRings.isEmpty {
                var transitionQueues = queuesBySource
                for (source, ring) in retiringRings {
                    transitionQueues[source, default: []].append(ring)
                }
                fanout.publish(AudioSourceFanout(
                    queuesBySource: transitionQueues,
                    inputChannelCounts: inputChannelCounts,
                    existing: prepared
                ))
            } else {
                fanout.publish(prepared)
            }
        }

        for route in routes where routeWork.contains(route.key) {
            guard let device = deviceByUID[route.uid], let renderer = renderers[route.key] else {
                output.stop(key: route.key)
                continue
            }
            if startOutputUnit(route, device: device, renderer: renderer) {
                activeRouteKeys.insert(route.key)
            }
        }
        if !retiringRings.isEmpty, let nextFanout {
            fanout.publish(nextFanout)
        }

        let previousSources = self.captureSources(for: lastGraph?.configuration, devices: lastDevices)
        let obsoleteSources = previousSources.subtracting(captureSources)
        let restartedSources = captureSourcesNeedingRestart(
            graph: graph,
            devices: orderedDevices,
            processes: orderedProcesses
        )
        for source in obsoleteSources {
            capture.stop(id: source)
        }
        for source in restartedSources {
            capture.stop(id: source)
        }
        let sourcesToStart = captureSources.subtracting(previousSources).union(restartedSources.intersection(captureSources))
        startCapture(sources: sourcesToStart, graph: graph, devices: deviceByUID, processes: processByID)
        if deviceRoutingChanged || lastEnabled != true ||
            lastGraph?.configuration.hiddenDeviceUIDs != graph.configuration.hiddenDeviceUIDs
        {
            updateDeviceMeters(devices: orderedDevices, hiddenUIDs: hiddenDeviceUIDs)
        }
        // Device and process changes can bypass the gain-only fast path. Make
        // sure surviving renderers still receive the newest global gains.
        republishGains(from: graph)
        remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
        return true
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    private func republishGains(from graph: MixGraphSnapshot) {
        for renderer in renderers.values {
            renderer.updateGains(from: graph)
        }
        for pump in busMeterPumps.values {
            pump.renderer.updateGains(from: graph)
        }
    }

    private func updateDeviceMeters(devices: [AudioDeviceSnapshot], hiddenUIDs: Set<String>) {
        let currentDevices = Dictionary(uniqueKeysWithValues: devices.filter { device in
            device.isAlive && device.outputChannels > 0 && !hiddenUIDs.contains(device.uid)
        }.map { ($0.uid, $0) })
        var nextMeters: [String: RealtimePeakMeter] = [:]
        for (uid, device) in currentDevices {
            if let previousDevice = deviceMeterDevices[uid],
               previousDevice.hasSameOutputRouting(as: device),
               let meter = deviceMeters[uid]
            {
                nextMeters[uid] = meter
                continue
            }
            if deviceMeterDevices[uid] != nil {
                capture.stop(id: "device:\(uid)")
            }
            let meter = RealtimePeakMeter()
            nextMeters[uid] = meter
            capture.startOutputMeter(uid: uid, meter: meter)
        }
        for uid in deviceMeterDevices.keys where currentDevices[uid] == nil {
            capture.stop(id: "device:\(uid)")
        }
        deviceMeters = nextMeters
        deviceMeterDevices = currentDevices
    }

    private func retainRenderMeters(for configuration: MixerConfiguration) {
        let nextMeterKeys = Set(Self.renderMeterKeys(configuration))
        renderMeters = renderMeters.filter { nextMeterKeys.contains($0.key) }
        for key in nextMeterKeys where renderMeters[key] == nil {
            renderMeters[key] = RealtimePeakMeter()
        }
    }

    private func routeRingsMatch(
        _ rings: [String: RealtimeAudioRingBuffer],
        route: RenderRoute,
        devices: [String: AudioDeviceSnapshot],
        buses: [VirtualBus]
    ) -> Bool {
        let keys = Self.sourceKeys(in: route.mix, buses: buses)
        guard Set(rings.keys) == Set(keys) else { return false }
        return keys.allSatisfy { key in
            rings[key]?.channelCount == sourceChannelCount(for: key, devices: devices, buses: buses)
        }
    }

    private func sourceChannelCount(for key: String, devices: [String: AudioDeviceSnapshot], buses: [VirtualBus] = []) -> Int {
        if key.hasPrefix("input:") {
            let uid = String(key.dropFirst("input:".count))
            return min(max(devices[uid]?.inputChannels ?? 2, 1), 64)
        }
        if key.hasPrefix("bus:") {
            let idText = String(key.dropFirst("bus:".count))
            return UUID(uuidString: idText).flatMap { id in buses.first(where: { $0.id == id })?.channelCount } ?? 2
        }
        return 2
    }

    private func captureSourcesNeedingRestart(
        graph: MixGraphSnapshot,
        devices: [AudioDeviceSnapshot],
        processes: [AudioProcessSnapshot]
    ) -> Set<String> {
        var result = Set<String>()
        let previousDevices = Dictionary(lastDevices.map { ($0.uid, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentDevices = Dictionary(devices.map { ($0.uid, $0) }, uniquingKeysWith: { _, latest in latest })
        let previousHidden = Set(lastGraph?.configuration.hiddenDeviceUIDs.map(\.rawValue) ?? [])
        let currentHidden = Set(graph.configuration.hiddenDeviceUIDs.map(\.rawValue))
        for uid in Set(previousDevices.keys).union(currentDevices.keys) {
            let previous = previousDevices[uid]
            let current = currentDevices[uid]
            let inputChanged = if let previous, let current {
                !previous.hasSameInputRouting(as: current)
            } else {
                true
            }
            if inputChanged || previousHidden.contains(uid) != currentHidden.contains(uid) {
                result.insert("input:\(uid)")
            }
        }
        let previousProcesses = Dictionary(lastProcesses.map { ($0.applicationID, $0) }, uniquingKeysWith: { _, latest in latest })
        let currentProcesses = Dictionary(processes.map { ($0.applicationID, $0) }, uniquingKeysWith: { _, latest in latest })
        for id in Set(previousProcesses.keys).union(currentProcesses.keys) {
            guard previousProcesses[id]?.processID != currentProcesses[id]?.processID ||
                previousProcesses[id]?.isProducingOutput != currentProcesses[id]?.isProducingOutput
            else { continue }
            result.insert("application:\(id)")
        }
        return result
    }

    func stop() {
        capture.stopAll()
        output.stopAll()
        renderers.removeAll()
        activeRouteKeys.removeAll()
        for pump in busMeterPumps.values {
            pump.stop()
        }
        busMeterPumps.removeAll()
        ringsByBusMeter.removeAll()
        busMeterSignatures.removeAll()
        ringsByRoute.removeAll()
        sourceMeters.removeAll()
        renderMeters.removeAll()
        deviceMeters.removeAll()
        deviceMeterDevices.removeAll()
        fanout.publish(nil)
        lastEnabled = false
    }

    private func needsUpdate(
        graph: MixGraphSnapshot,
        devices: [AudioDeviceSnapshot],
        processes: [AudioProcessSnapshot],
        enabled: Bool
    ) -> Bool {
        lastGraph != graph || lastDevices.count != devices.count ||
            !zip(lastDevices, devices).allSatisfy { $0.hasSameRouting(as: $1) } ||
            !Self.hasSameProcessRouting(lastProcesses, processes) || lastEnabled != enabled
    }

    private static func hasSameProcessRouting(
        _ lhs: [AudioProcessSnapshot],
        _ rhs: [AudioProcessSnapshot]
    ) -> Bool {
        func identities(_ processes: [AudioProcessSnapshot]) -> [RuntimeProcessRoutingIdentity] {
            processes.map {
                RuntimeProcessRoutingIdentity(
                    applicationID: $0.applicationID,
                    processID: $0.processID,
                    isProducingOutput: $0.isProducingOutput
                )
            }
        }
        return RuntimeProcessRoutingIdentity.matches(identities(lhs), identities(rhs))
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
        activeRouteKeys.removeAll()
        for pump in busMeterPumps.values {
            pump.stop()
        }
        busMeterPumps.removeAll()
        ringsByBusMeter.removeAll()
        busMeterSignatures.removeAll()
        ringsByRoute.removeAll()
        sourceMeters.removeAll()
        renderMeters.removeAll()
        deviceMeters.removeAll()
        deviceMeterDevices.removeAll()
        fanout.publish(nil)
    }

    // The queue and source collections are populated together for a single fanout snapshot.
    // swiftlint:disable:next function_parameter_count
    private func reconcileBusMeters(
        graph: MixGraphSnapshot,
        shape: RuntimeGraphShape,
        devices: [String: AudioDeviceSnapshot],
        changedMutedSources: Set<SourceReference>,
        changedMutedBuses: Set<UUID>,
        queues: inout [String: [RealtimeAudioRingBuffer]],
        sources: inout Set<String>
    ) {
        let desiredIDs = Set(graph.configuration.buses.map(\.id))
        for id in Array(busMeterPumps.keys) where !desiredIDs.contains(id) {
            busMeterPumps.removeValue(forKey: id)?.stop()
            ringsByBusMeter.removeValue(forKey: id)
            busMeterSignatures.removeValue(forKey: id)
        }
        for bus in graph.configuration.buses {
            guard !bus.mix.inputs.isEmpty else {
                busMeterPumps.removeValue(forKey: bus.id)?.stop()
                ringsByBusMeter.removeValue(forKey: bus.id)
                busMeterSignatures.removeValue(forKey: bus.id)
                continue
            }
            let sourceKeys = Self.sourceKeys(in: bus.mix, buses: graph.configuration.buses)
            let inputChannels = Dictionary(uniqueKeysWithValues: sourceKeys.compactMap { source -> (String, Int)? in
                guard source.hasPrefix("input:") else { return nil }
                let uid = String(source.dropFirst("input:".count))
                return (source, min(max(devices[uid]?.inputChannels ?? 2, 1), 64))
            })
            let rootMix = Mix(inputs: [MixInput(source: .bus(bus.id))])
            let signature = BusMeterSignature(
                dependencies: shape.busDependenciesByID[bus.id] ?? [],
                inputChannels: inputChannels
            )
            if busMeterPumps[bus.id] == nil || busMeterSignatures[bus.id] != signature {
                busMeterPumps.removeValue(forKey: bus.id)?.stop()
                let prepared = makeBusMeterPump(
                    bus: bus, graph: graph, devices: devices, sourceKeys: sourceKeys, rootMix: rootMix
                )
                ringsByBusMeter[bus.id] = prepared.rings
                busMeterPumps[bus.id] = prepared.pump
                busMeterSignatures[bus.id] = signature
                prepared.pump.start()
            } else if busMeterPumps[bus.id]?.renderer.depends(
                on: changedMutedSources, changedBuses: changedMutedBuses
            ) == true {
                busMeterPumps[bus.id]?.renderer.updateGains(from: graph)
            }
            for (source, ring) in ringsByBusMeter[bus.id] ?? [:] {
                queues[source, default: []].append(ring)
                sources.insert(source)
            }
        }
    }

    private func makeBusMeterPump(
        bus: VirtualBus,
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        sourceKeys: [String],
        rootMix: Mix
    ) -> (pump: BusMeterPump, rings: [String: RealtimeAudioRingBuffer]) {
        var rings: [String: RealtimeAudioRingBuffer] = [:]
        for key in sourceKeys {
            let channels: Int
            if key.hasPrefix("input:") {
                let uid = String(key.dropFirst("input:".count))
                channels = min(max(devices[uid]?.inputChannels ?? 2, 1), 64)
            } else if key.hasPrefix("bus:") {
                let idText = String(key.dropFirst("bus:".count))
                channels = UUID(uuidString: idText).flatMap { id in
                    graph.configuration.buses.first(where: { $0.id == id })?.channelCount
                } ?? 2
            } else {
                channels = 2
            }
            rings[key] = RealtimeAudioRingBuffer(channelCount: channels)
        }
        let meterPrefix = "bus:\(bus.id.uuidString)/"
        let renderer = AudioGraphRenderer(
            graph: graph,
            output: OutputMix(deviceUID: DeviceUID(rawValue: "virtual-meter"), mix: rootMix),
            sourceRings: rings,
            targetKey: "virtual-meter",
            meters: renderMeters.filter { $0.key.hasPrefix(meterPrefix) }
        )
        renderer.updateGains(from: graph)
        return (BusMeterPump(renderer: renderer), rings)
    }

    private func startOutputRoute(
        _ route: RenderRoute,
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        existingRings: [String: RealtimeAudioRingBuffer]
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
            let channelCount = sourceChannelCount(for: key, devices: devices, buses: graph.configuration.buses)
            if let existing = existingRings[key], existing.channelCount == channelCount {
                // The route keeps the same HAL callback; publishing the new renderer transfers its existing queues.
                return (key, existing)
            }
            return (key, RealtimeAudioRingBuffer(channelCount: channelCount))
        })
        let renderer = AudioGraphRenderer(
            graph: graph,
            output: OutputMix(deviceUID: DeviceUID(rawValue: route.uid), mix: route.mix),
            sourceRings: rings,
            outputChannelCount: route.channels.count,
            targetKey: route.targetKey,
            meters: renderMeters.filter { $0.key.hasPrefix("\(route.targetKey)/") || $0.key.hasPrefix("bus:") }
        )
        renderer.updateGains(from: graph)
        renderers[route.key] = renderer
        return rings
    }

    private func startOutputUnit(
        _ route: RenderRoute,
        device: AudioDeviceSnapshot,
        renderer: AudioGraphRenderer
    ) -> Bool {
        do {
            try output.start(
                route: CoreAudioOutputCoordinator.Route(
                    key: route.key,
                    deviceUID: device.uid,
                    deviceID: device.deviceID,
                    deviceChannelCount: device.outputChannels,
                    selectedChannels: route.channels,
                    sampleRate: 48000
                ),
                render: { channels, frames in renderer.render(channels: channels, frameCount: frames) }
            )
            return true
        } catch {
            output.stop(key: route.key)
            onRouteError?(route.key, error.localizedDescription)
            return false
        }
    }

    private static func hasOnlyRoutingChanges(from old: MixerConfiguration, to new: MixerConfiguration) -> Bool {
        guard old != new else { return false }
        func normalized(_ source: MixerConfiguration) -> MixerConfiguration {
            var copy = source
            for index in copy.outputMixes.indices {
                Self.clearRouting(&copy.outputMixes[index].mix)
            }
            for index in copy.buses.indices {
                Self.clearRouting(&copy.buses[index].mix)
            }
            return copy
        }
        return normalized(old) == normalized(new)
    }

    private static func clearRouting(_ mix: inout Mix) {
        for index in mix.inputs.indices {
            mix.inputs[index].channelRouting = Array(repeating: [], count: mix.inputs[index].channelRouting.count)
        }
    }

    private static func hasOnlyGainChanges(from old: MixerConfiguration, to new: MixerConfiguration) -> Bool {
        func normalized(_ source: MixerConfiguration) -> MixerConfiguration {
            var copy = source
            func normalize(_ mix: inout Mix) {
                mix.level = 1
                for index in mix.inputs.indices {
                    mix.inputs[index].level = 1
                    mix.inputs[index].channelLevels = Array(repeating: 1, count: mix.inputs[index].channelLevels.count)
                    mix.inputs[index].channelRouting = Array(repeating: [], count: mix.inputs[index].channelRouting.count)
                }
            }
            for index in copy.outputMixes.indices {
                normalize(&copy.outputMixes[index].mix)
            }
            for index in copy.buses.indices {
                normalize(&copy.buses[index].mix)
            }
            copy.mutedBuses = []
            copy.mutedSources = []
            copy.sourceLevels = []
            return copy
        }
        return normalized(old) == normalized(new)
    }

    private func startCapture(
        sources: Set<String>,
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        processes: [String: AudioProcessSnapshot]
    ) {
        let hiddenUIDs = Set(graph.configuration.hiddenDeviceUIDs.map(\.rawValue))
        for source in sources {
            if source.hasPrefix("input:") {
                startInput(source: source, devices: devices, hiddenUIDs: hiddenUIDs)
            } else if source.hasPrefix("application:") {
                startApplication(source: source, processes: processes)
            }
        }
    }

    private func startInput(source: String, devices: [String: AudioDeviceSnapshot], hiddenUIDs: Set<String>) {
        let uid = String(source.dropFirst("input:".count))
        guard !hiddenUIDs.contains(uid), let device = devices[uid], device.isAlive, device.inputChannels > 0 else { return }
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
        let current = fanout.beginRead()
        defer { fanout.endRead() }
        return current?.channelReadingsBySource ?? [:]
    }

    func renderLevelReadings() -> [String: Double] {
        renderMeters.compactMapValues { $0.reading() }
    }

    func deviceLevelReadings() -> [String: Double] {
        deviceMeters.compactMapValues { $0.reading() }
    }

    private func hasSameFanoutTopology(
        queuesBySource: [String: [RealtimeAudioRingBuffer]],
        inputChannelCounts: [String: Int]
    ) -> Bool {
        let current = fanout.beginRead()
        defer { fanout.endRead() }
        return current?.hasSameTopology(
            queuesBySource: queuesBySource,
            inputChannelCounts: inputChannelCounts
        ) ?? false
    }

    private func makeFanoutSnapshot(
        queuesBySource: [String: [RealtimeAudioRingBuffer]],
        inputChannelCounts: [String: Int]
    ) -> AudioSourceFanout {
        let current = fanout.beginRead()
        defer { fanout.endRead() }
        return AudioSourceFanout(
            queuesBySource: queuesBySource,
            inputChannelCounts: inputChannelCounts,
            existing: current
        )
    }
}

/// Drives virtual-bus rendering when no physical output consumes it.
/// The scratch buffers are allocated once; the timer callback only renders and meters.
private final class BusMeterPump {
    let renderer: AudioGraphRenderer
    private let queue = DispatchQueue(label: "com.rlz.soundmixer.virtual-bus-meter", qos: .userInitiated)
    private let frameCount = 480
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let planePointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private var timer: DispatchSourceTimer?

    init(renderer: AudioGraphRenderer) {
        self.renderer = renderer
        left = .allocate(capacity: frameCount)
        right = .allocate(capacity: frameCount)
        left.initialize(repeating: 0, count: frameCount)
        right.initialize(repeating: 0, count: frameCount)
        planePointers = .allocate(capacity: 2)
        planePointers.initialize(to: left)
        planePointers.advanced(by: 1).initialize(to: right)
    }

    deinit {
        left.deinitialize(count: frameCount)
        right.deinitialize(count: frameCount)
        left.deallocate()
        right.deallocate()
        planePointers.deinitialize(count: 2)
        planePointers.deallocate()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            renderer.render(channels: UnsafeBufferPointer(start: planePointers, count: 2), frameCount: frameCount)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        guard let timer else { return }
        self.timer = nil
        timer.cancel()
        queue.sync {}
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
        for bus in configuration.buses {
            let target = "bus:\(bus.id.uuidString)"
            keys.append("\(target)/destination")
            keys += (1 ... bus.channelCount).map { "\(target)/channel/\($0)" }
            keys += bus.mix.inputs.map { "\(target)/\(AudioGraphRenderer.sourceMeterKey($0.source))" }
        }
        return keys
    }

    private func captureSources(
        for configuration: MixerConfiguration?,
        devices: [AudioDeviceSnapshot]
    ) -> Set<String> {
        guard let configuration, configuration.isEnabled else { return [] }
        let hiddenUIDs = Set(configuration.hiddenDeviceUIDs.map(\.rawValue))
        var sources = Set(devices.filter { $0.inputChannels > 0 && !hiddenUIDs.contains($0.uid) }.map { "input:\($0.uid)" })
        sources.formUnion(configuration.applications.map { "application:\($0.rawValue)" })
        for route in makeRoutes(configuration, devices: devices) {
            sources.formUnion(Self.sourceKeys(in: route.mix, buses: configuration.buses))
        }
        for bus in configuration.buses {
            sources.formUnion(Self.sourceKeys(in: bus.mix, buses: configuration.buses))
        }
        return sources
    }

    private func makeRoutes(_ configuration: MixerConfiguration, devices: [AudioDeviceSnapshot]) -> [RenderRoute] {
        let hiddenUIDs = Set(configuration.hiddenDeviceUIDs.map(\.rawValue))
        return configuration.outputMixes.filter { !hiddenUIDs.contains($0.deviceUID.rawValue) }.map { output in
            var mix = output.mix
            mix.level = 1
            return RenderRoute(
                key: "output:\(output.deviceUID.rawValue)",
                uid: output.deviceUID.rawValue,
                channels: Array(0 ..< max(devices.first(where: { $0.uid == output.deviceUID.rawValue })?.outputChannels ?? 2, 1)),
                mix: mix,
                targetKey: "output:\(output.deviceUID.rawValue)"
            )
        }
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

private struct BusMeterSignature: Equatable {
    let dependencies: [RuntimeBusRenderingDefinition]
    let inputChannels: [String: Int]
}
