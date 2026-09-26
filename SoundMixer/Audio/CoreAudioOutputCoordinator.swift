import AudioToolbox
import CoreAudio
import Foundation

/// Owns one HAL output unit per Core Audio device. Routes using separate channel
/// pairs share that unit, so adding a pair only publishes a new render snapshot.
final class CoreAudioOutputCoordinator {
    typealias StereoRenderHandler = (UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<Float>, Int) -> Void

    struct Route {
        let key: String
        let deviceID: AudioDeviceID
        let deviceChannelCount: Int
        let selectedChannels: [Int]
        let sampleRate: Double
    }

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.audio-output")
    private var sessions: [AudioDeviceID: OutputSession] = [:]
    private var deviceByRouteKey: [String: AudioDeviceID] = [:]

    func start(route: Route, render: @escaping StereoRenderHandler) throws {
        guard !route.key.isEmpty, route.deviceChannelCount > 0,
              (1 ... 2).contains(route.selectedChannels.count),
              Set(route.selectedChannels).count == route.selectedChannels.count,
              route.selectedChannels.allSatisfy({ (0 ..< route.deviceChannelCount).contains($0) }),
              route.sampleRate.isFinite, route.sampleRate > 0
        else { throw OutputError.invalidRoute }

        try queue.sync {
            if let oldDeviceID = deviceByRouteKey[route.key], oldDeviceID != route.deviceID {
                removeRouteOnQueue(key: route.key)
            }
            if let existing = sessions[route.deviceID], existing.canReuseHardware(for: route) {
                existing.update(route: route, render: render)
                deviceByRouteKey[route.key] = route.deviceID
                return
            }
            if let obsolete = sessions.removeValue(forKey: route.deviceID) {
                for key in obsolete.routeKeys {
                    deviceByRouteKey.removeValue(forKey: key)
                }
                obsolete.stop()
            }
            let session = OutputSession(route: route, render: render)
            try session.start()
            sessions[route.deviceID] = session
            deviceByRouteKey[route.key] = route.deviceID
        }
    }

    func stop(key: String) {
        queue.sync {
            removeRouteOnQueue(key: key)
        }
    }

    private func removeRouteOnQueue(key: String) {
        guard let deviceID = deviceByRouteKey.removeValue(forKey: key), let session = sessions[deviceID] else { return }
        session.remove(key: key)
        if session.routeKeys.isEmpty {
            sessions.removeValue(forKey: deviceID)?.stop()
        }
    }

    func stopAll() {
        queue.sync {
            for session in sessions.values {
                session.stop()
            }
            sessions.removeAll()
            deviceByRouteKey.removeAll()
        }
    }

    private final class OutputSession {
        let deviceID: AudioDeviceID
        let deviceChannelCount: Int
        let sampleRate: Double
        private var routes: [String: RouteRender]
        private let publication: RealtimePublication<RouteSnapshot>
        var routeKeys: Set<String> {
            Set(routes.keys)
        }

        let maximumFrames = 8192
        let left: UnsafeMutablePointer<Float>
        let right: UnsafeMutablePointer<Float>
        var unit: AudioUnit?

        init(route: Route, render: @escaping StereoRenderHandler) {
            deviceID = route.deviceID
            deviceChannelCount = route.deviceChannelCount
            sampleRate = route.sampleRate
            let prepared = RouteRender(key: route.key, channels: route.selectedChannels, render: render)
            routes = [route.key: prepared]
            publication = RealtimePublication(RouteSnapshot(routes: [prepared]))
            left = .allocate(capacity: maximumFrames)
            right = .allocate(capacity: maximumFrames)
            left.initialize(repeating: 0, count: maximumFrames)
            right.initialize(repeating: 0, count: maximumFrames)
        }

        func canReuseHardware(for route: Route) -> Bool {
            deviceID == route.deviceID && deviceChannelCount == route.deviceChannelCount &&
                sampleRate == route.sampleRate
        }

        func update(route: Route, render: @escaping StereoRenderHandler) {
            routes[route.key] = RouteRender(key: route.key, channels: route.selectedChannels, render: render)
            publishRoutes()
        }

        func remove(key: String) {
            routes.removeValue(forKey: key)
            if !routes.isEmpty {
                publishRoutes()
            }
        }

        private func publishRoutes() {
            publication.publish(RouteSnapshot(routes: routes.values.sorted { $0.key < $1.key }))
        }

        deinit {
            left.deinitialize(count: maximumFrames)
            right.deinitialize(count: maximumFrames)
            left.deallocate()
            right.deallocate()
        }

        func start() throws {
            var description = AudioComponentDescription(
                componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard let component = AudioComponentFindNext(nil, &description) else {
                throw OutputError.outputUnitUnavailable
            }
            var created: AudioUnit?
            try Self.check(AudioComponentInstanceNew(component, &created))
            guard let created else { throw OutputError.outputUnitUnavailable }
            unit = created

            do {
                var enable: UInt32 = 1
                var disable: UInt32 = 0
                var selectedDevice = deviceID
                try Self.set(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable)
                try Self.set(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable)
                try Self.set(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selectedDevice)

                var streamFormat = AudioStreamBasicDescription(
                    mSampleRate: sampleRate,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: UInt32(deviceChannelCount * MemoryLayout<Float>.size),
                    mFramesPerPacket: 1,
                    mBytesPerFrame: UInt32(deviceChannelCount * MemoryLayout<Float>.size),
                    mChannelsPerFrame: UInt32(deviceChannelCount),
                    mBitsPerChannel: 32,
                    mReserved: 0
                )
                try Self.set(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamFormat)
                var callback = AURenderCallbackStruct(
                    inputProc: Self.outputCallback,
                    inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
                )
                try Self.set(created, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback)
                try Self.check(AudioUnitInitialize(created))
                try Self.check(AudioOutputUnitStart(created))
            } catch {
                AudioOutputUnitStop(created)
                AudioUnitUninitialize(created)
                AudioComponentInstanceDispose(created)
                unit = nil
                throw error
            }
        }

        func stop() {
            guard let unit else { return }
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            self.unit = nil
        }

        private static let outputCallback: AURenderCallback = { reference, _, _, _, frameCount, data in
            guard let data else { return kAudio_ParamError }
            let session = Unmanaged<OutputSession>.fromOpaque(reference).takeUnretainedValue()
            let frames = Int(frameCount)
            guard frames <= session.maximumFrames else { return kAudio_ParamError }
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            guard buffers.count == 1,
                  buffers[0].mNumberChannels == UInt32(session.deviceChannelCount),
                  let raw = buffers[0].mData,
                  buffers[0].mDataByteSize >= UInt32(frames * session.deviceChannelCount * MemoryLayout<Float>.size)
            else { return kAudio_ParamError }

            let sampleCount = frames * session.deviceChannelCount
            let output = raw.assumingMemoryBound(to: Float.self)
            output.update(repeating: 0, count: sampleCount)
            let left = UnsafeMutableBufferPointer(start: session.left, count: frames)
            let right = UnsafeMutableBufferPointer(start: session.right, count: frames)
            let snapshot = session.publication.beginRead()
            defer { session.publication.endRead() }
            if let snapshot {
                for route in snapshot.routes {
                    left.update(repeating: 0)
                    right.update(repeating: 0)
                    route.render(left, right, frames)
                    if route.channels.count == 1 {
                        let channel = route.channels[0]
                        for frame in 0 ..< frames {
                            output[frame * session.deviceChannelCount + channel] = (left[frame] + right[frame]) * 0.5
                        }
                    } else {
                        let leftChannel = route.channels[0]
                        let rightChannel = route.channels[1]
                        for frame in 0 ..< frames {
                            output[frame * session.deviceChannelCount + leftChannel] = left[frame]
                            output[frame * session.deviceChannelCount + rightChannel] = right[frame]
                        }
                    }
                }
            }
            buffers[0].mDataByteSize = UInt32(sampleCount * MemoryLayout<Float>.size)
            return noErr
        }

        private static func set(
            _ unit: AudioUnit,
            _ property: AudioUnitPropertyID,
            _ scope: AudioUnitScope,
            _ element: AudioUnitElement,
            _ value: inout some Any
        ) throws {
            let status = withUnsafeBytes(of: &value) { bytes in
                AudioUnitSetProperty(unit, property, scope, element, bytes.baseAddress, UInt32(bytes.count))
            }
            try check(status)
        }

        private static func check(_ status: OSStatus) throws {
            guard status == noErr else { throw OutputError.audioStatus(status) }
        }
    }

    private enum OutputError: LocalizedError {
        case invalidRoute
        case outputUnitUnavailable
        case audioStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidRoute: "The output route has invalid channels or format."
            case .outputUnitUnavailable: "The Core Audio HAL output unit is unavailable."
            case let .audioStatus(status): "Core Audio output failed with status \(status)."
            }
        }
    }
}

private struct RouteRender {
    let key: String
    let channels: [Int]
    let render: CoreAudioOutputCoordinator.StereoRenderHandler
}

private final class RouteSnapshot {
    let routes: [RouteRender]

    init(routes: [RouteRender]) {
        self.routes = routes
    }
}
