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
    private var ringsByRoute: [String: [String: RealtimeStereoRingBuffer]] = [:]
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

    func update(graph: MixGraphSnapshot, devices: [AudioDeviceSnapshot], processes: [AudioProcessSnapshot]) {
        let orderedDevices = devices.sorted { $0.uid < $1.uid }
        let orderedProcesses = processes.sorted {
            $0.applicationID == $1.applicationID ? $0.processID < $1.processID : $0.applicationID < $1.applicationID
        }
        let enabled = graph.configuration.isEnabled
        guard needsUpdate(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled) else { return }
        remember(graph: graph, devices: orderedDevices, processes: orderedProcesses, enabled: enabled)
        stopCurrentRouting()
        guard enabled else { return }

        let deviceByUID = Dictionary(orderedDevices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let processByID = Dictionary(orderedProcesses.map { ($0.applicationID, $0) }, uniquingKeysWith: { first, _ in first })
        var queuesBySource: [String: [RealtimeStereoRingBuffer]] = [:]
        var captureSources = Set<String>()
        startOutputRoutes(graph: graph, devices: deviceByUID, queues: &queuesBySource, sources: &captureSources)
        fanout = AudioSourceFanout(queuesBySource: queuesBySource)
        startCapture(sources: captureSources, devices: deviceByUID, processes: processByID)
    }

    func stop() {
        capture.stopAll()
        output.stopAll()
        renderers.removeAll()
        ringsByRoute.removeAll()
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
        fanout = nil
    }

    private func startOutputRoutes(
        graph: MixGraphSnapshot,
        devices: [String: AudioDeviceSnapshot],
        queues: inout [String: [RealtimeStereoRingBuffer]],
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
    ) -> [String: RealtimeStereoRingBuffer]? {
        guard let device = devices[route.uid], device.isAlive,
              route.channels.max().map({ device.outputChannels > $0 }) ?? false,
              device.nominalSampleRate.isFinite, device.nominalSampleRate > 0
        else {
            onRouteError?(route.key, "The selected output device or channels are unavailable.")
            return nil
        }

        let sourceKeys = Self.sourceKeys(in: route.mix, buses: graph.configuration.buses)
        let rings = Dictionary(uniqueKeysWithValues: sourceKeys.map { ($0, RealtimeStereoRingBuffer()) })
        let monoSourceKeys = Set(devices.values.filter { $0.inputChannels == 1 }.map { "input:\($0.uid)" })
        let renderer = AudioGraphRenderer(
            graph: graph,
            output: OutputMix(deviceUID: DeviceUID(rawValue: route.uid), mix: route.mix),
            sourceRings: rings,
            monoSourceKeys: monoSourceKeys
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
        devices: [String: AudioDeviceSnapshot],
        processes: [String: AudioProcessSnapshot]
    ) {
        for source in sources {
            if source.hasPrefix("input:") {
                startInput(source: source, devices: devices)
            } else if source.hasPrefix("application:") {
                startApplication(source: source, processes: processes)
            }
        }
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

    private func makeRoutes(_ configuration: MixerConfiguration) -> [RenderRoute] {
        var routes = configuration.outputMixes.map { output in
            RenderRoute(key: "output:\(output.deviceUID.rawValue)", uid: output.deviceUID.rawValue, channels: [0, 1], mix: output.mix)
        }
        routes += configuration.blackHoleRoutes.map { route in
            let channels: [Int] = switch route.channels {
            case let .mono(channel): [channel - 1]
            case let .stereo(left, right): [left - 1, right - 1]
            }
            return RenderRoute(key: "blackhole:\(route.id.uuidString)", uid: route.deviceUID.rawValue, channels: channels, mix: route.mix)
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
}

/// Converts captured Float32 input to the 48 kHz planar format used by renderers.
/// It fans each source into a distinct SPSC queue for every configured endpoint.
private final class AudioSourceFanout {
    private let queuesBySource: [String: [RealtimeStereoRingBuffer]]
    private let buffersBySource: [String: SourceBuffer]
    private let capacity = 8192

    init(queuesBySource: [String: [RealtimeStereoRingBuffer]]) {
        self.queuesBySource = queuesBySource
        buffersBySource = Dictionary(uniqueKeysWithValues: queuesBySource.keys.map { ($0, SourceBuffer(capacity: 8192)) })
    }

    func consume(id: String, buffers: UnsafePointer<AudioBufferList>, frames: UInt32, format: AudioStreamBasicDescription) {
        guard let queues = queuesBySource[id], let storage = buffersBySource[id], !queues.isEmpty,
              let converted = storage.convert(buffers: buffers, frames: frames, format: format)
        else { return }
        let sourceLeft = UnsafeBufferPointer(start: storage.left, count: converted.frameCount)
        let sourceRight = UnsafeBufferPointer(start: storage.right, count: converted.frameCount)
        for queue in queues {
            if converted.droppedFrames > 0 {
                queue.recordDroppedFrames(converted.droppedFrames)
            }
            _ = queue.write(left: sourceLeft, right: sourceRight, frameCount: converted.frameCount)
        }
    }
}

struct AudioQueueDiagnostics: Equatable {
    let droppedFrames: Int64
    let underrunFrames: Int64
}

private final class SourceBuffer {
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    private let capacity: Int
    var outputRemainder = 0.0

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

    func convert(
        buffers: UnsafePointer<AudioBufferList>,
        frames: UInt32,
        format: AudioStreamBasicDescription
    ) -> (frameCount: Int, droppedFrames: Int)? {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame > 0,
              format.mSampleRate.isFinite,
              (8000 ... 384_000).contains(format.mSampleRate)
        else { return nil }

        let inputFrames = Int(frames)
        guard inputFrames > 0, inputFrames <= capacity else { return nil }
        let channelCount = Int(format.mChannelsPerFrame)
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard let firstData = list.first?.mData else { return nil }
        let first = firstData.assumingMemoryBound(to: Float.self)
        let second = rightChannel(list: list, formatIsNonInterleaved: nonInterleaved, channelCount: channelCount)
        guard hasEnoughData(list: list, inputFrames: inputFrames, channelCount: channelCount, nonInterleaved: nonInterleaved)
        else { return nil }

        let expectedFrames = Double(inputFrames) * 48000 / format.mSampleRate + outputRemainder
        let convertedFrames = Int(expectedFrames)
        outputRemainder = expectedFrames - Double(convertedFrames)
        let outputFrames = min(capacity, convertedFrames)
        guard outputFrames > 0 else { return nil }
        let source = AudioInputView(
            channelCount: channelCount,
            nonInterleaved: nonInterleaved,
            first: first,
            second: second,
            sampleRate: format.mSampleRate
        )
        resample(frames: outputFrames, inputFrames: inputFrames, source: source)
        return (outputFrames, convertedFrames - outputFrames)
    }

    private func rightChannel(
        list: UnsafeMutableAudioBufferListPointer,
        formatIsNonInterleaved: Bool,
        channelCount: Int
    ) -> UnsafePointer<Float>? {
        guard formatIsNonInterleaved, channelCount > 1, list.count > 1, let data = list[1].mData else { return nil }
        return UnsafePointer(data.assumingMemoryBound(to: Float.self))
    }

    private func hasEnoughData(
        list: UnsafeMutableAudioBufferListPointer,
        inputFrames: Int,
        channelCount: Int,
        nonInterleaved: Bool
    ) -> Bool {
        let sampleSize = MemoryLayout<Float>.size
        let requiredBytes = inputFrames * (nonInterleaved ? sampleSize : channelCount * sampleSize)
        guard Int(list[0].mDataByteSize) >= requiredBytes else { return false }
        return !nonInterleaved || channelCount == 1 || (list.count > 1 && Int(list[1].mDataByteSize) >= inputFrames * sampleSize)
    }

    private func resample(frames: Int, inputFrames: Int, source: AudioInputView) {
        for frame in 0 ..< frames {
            let position = min(Double(inputFrames - 1), Double(frame) * source.sampleRate / 48000)
            let inputFrame = Int(position)
            let nextFrame = min(inputFrames - 1, inputFrame + 1)
            let fraction = Float(position - Double(inputFrame))
            let leftStart: Float
            let leftEnd: Float
            let rightStart: Float
            let rightEnd: Float
            if source.nonInterleaved {
                let right = source.second ?? source.first
                leftStart = source.first[inputFrame]
                leftEnd = source.first[nextFrame]
                rightStart = source.channelCount > 1 ? right[inputFrame] : leftStart
                rightEnd = source.channelCount > 1 ? right[nextFrame] : leftEnd
            } else {
                let base = inputFrame * source.channelCount
                let nextBase = nextFrame * source.channelCount
                leftStart = source.first[base]
                leftEnd = source.first[nextBase]
                rightStart = source.channelCount > 1 ? source.first[base + 1] : leftStart
                rightEnd = source.channelCount > 1 ? source.first[nextBase + 1] : leftEnd
            }
            left[frame] = leftStart + (leftEnd - leftStart) * fraction
            right[frame] = rightStart + (rightEnd - rightStart) * fraction
        }
    }
}

private struct AudioInputView {
    let channelCount: Int
    let nonInterleaved: Bool
    let first: UnsafePointer<Float>
    let second: UnsafePointer<Float>?
    let sampleRate: Double
}
