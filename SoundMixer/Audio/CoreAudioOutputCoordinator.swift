import AudioToolbox
import CoreAudio
import Foundation

// Owns one HAL output unit per Core Audio device and publishes channel snapshots to it.
// Session ownership and device-disconnect monitoring share one serial queue.
// swiftlint:disable:next type_body_length
final class CoreAudioOutputCoordinator {
    typealias RenderHandler = (UnsafeBufferPointer<UnsafeMutablePointer<Float>>, Int) -> Void

    struct Route {
        let key: String
        let deviceUID: String
        let deviceID: AudioDeviceID
        let deviceChannelCount: Int
        let selectedChannels: [Int]
        let sampleRate: Double
    }

    private let queue = DispatchQueue(label: "com.rlz.soundmixer.audio-output")
    private var sessions: [AudioDeviceID: OutputSession] = [:]
    private var deviceByRouteKey: [String: AudioDeviceID] = [:]
    private var deviceListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    func start(route: Route, render: @escaping RenderHandler) throws {
        guard !route.key.isEmpty, route.deviceChannelCount > 0,
              !route.selectedChannels.isEmpty,
              Set(route.selectedChannels).count == route.selectedChannels.count,
              route.selectedChannels.allSatisfy({ (0 ..< route.deviceChannelCount).contains($0) }),
              route.sampleRate.isFinite, route.sampleRate > 0
        else { throw OutputError.invalidRoute }

        try queue.sync {
            try Self.validateDevice(route.deviceID, expectedUID: route.deviceUID)
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
                removeDeviceListener(for: route.deviceID)
            }
            let session = OutputSession(route: route, render: render)
            try installDeviceListener(for: route.deviceID)
            do {
                try session.start()
            } catch {
                removeDeviceListener(for: route.deviceID)
                throw error
            }
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
            removeDeviceListener(for: deviceID)
        }
    }

    private func installDeviceListener(for deviceID: AudioDeviceID) throws {
        guard deviceListeners[deviceID] == nil else { return }
        var address = Self.deviceAliveAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let session = sessions[deviceID] else { return }
            do {
                try Self.validateDevice(deviceID, expectedUID: session.deviceUID)
            } catch {
                removeDeviceOnQueue(deviceID)
            }
        }
        guard AudioObjectAddPropertyListenerBlock(deviceID, &address, queue, listener) == noErr else {
            throw OutputError.deviceMonitoringUnavailable
        }
        deviceListeners[deviceID] = listener
    }

    private func removeDeviceListener(for deviceID: AudioDeviceID) {
        guard let listener = deviceListeners.removeValue(forKey: deviceID) else { return }
        var address = Self.deviceAliveAddress
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, queue, listener)
    }

    private func removeDeviceOnQueue(_ deviceID: AudioDeviceID) {
        guard let session = sessions.removeValue(forKey: deviceID) else { return }
        for key in session.routeKeys {
            deviceByRouteKey.removeValue(forKey: key)
        }
        session.stop()
        removeDeviceListener(for: deviceID)
    }

    func stopAll() {
        queue.sync {
            for session in sessions.values {
                session.stop()
            }
            for deviceID in Array(deviceListeners.keys) {
                removeDeviceListener(for: deviceID)
            }
            sessions.removeAll()
            deviceByRouteKey.removeAll()
        }
    }

    private static var deviceAliveAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func validateDevice(_ deviceID: AudioDeviceID, expectedUID: String) throws {
        var aliveAddress = deviceAliveAddress
        var alive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &aliveAddress, 0, nil, &aliveSize, &alive) == noErr,
              alive == 1
        else { throw OutputError.deviceUnavailable }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr,
              let uid, (uid.takeRetainedValue() as String) == expectedUID
        else { throw OutputError.deviceChanged }
    }

    private final class OutputSession {
        let deviceID: AudioDeviceID
        let deviceUID: String
        let deviceChannelCount: Int
        let sampleRate: Double
        private var routes: [String: RouteRender]
        private let publication: RealtimePublication<RouteSnapshot>
        var routeKeys: Set<String> {
            Set(routes.keys)
        }

        let maximumFrames = 8192
        let planes: [UnsafeMutablePointer<Float>]
        let planePointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
        var unit: AudioUnit?

        init(route: Route, render: @escaping RenderHandler) {
            deviceID = route.deviceID
            deviceUID = route.deviceUID
            deviceChannelCount = route.deviceChannelCount
            sampleRate = route.sampleRate
            let prepared = RouteRender(key: route.key, channels: route.selectedChannels, render: render)
            routes = [route.key: prepared]
            publication = RealtimePublication(RouteSnapshot(routes: [prepared]))
            planes = (0 ..< route.deviceChannelCount).map { _ in
                let plane = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
                plane.initialize(repeating: 0, count: 8192)
                return plane
            }
            planePointers = .allocate(capacity: planes.count)
            for index in planes.indices {
                planePointers.advanced(by: index).initialize(to: planes[index])
            }
        }

        func canReuseHardware(for route: Route) -> Bool {
            deviceID == route.deviceID && deviceUID == route.deviceUID && deviceChannelCount == route.deviceChannelCount &&
                sampleRate == route.sampleRate
        }

        func update(route: Route, render: @escaping RenderHandler) {
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
            for plane in planes {
                plane.deinitialize(count: maximumFrames)
                plane.deallocate()
            }
            planePointers.deinitialize(count: planes.count)
            planePointers.deallocate()
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
            let snapshot = session.publication.beginRead()
            defer { session.publication.endRead() }
            if let snapshot {
                for route in snapshot.routes {
                    for index in route.channels.indices {
                        session.planes[index].update(repeating: 0, count: frames)
                    }
                    route.render(UnsafeBufferPointer(start: session.planePointers, count: route.channels.count), frames)
                    for (index, channel) in route.channels.enumerated() {
                        let plane = session.planes[index]
                        for frame in 0 ..< frames {
                            output[frame * session.deviceChannelCount + channel] = plane[frame]
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
        case deviceUnavailable
        case deviceChanged
        case deviceMonitoringUnavailable
        case outputUnitUnavailable
        case audioStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidRoute: "The output route has invalid channels or format."
            case .deviceUnavailable: "The selected output device is unavailable."
            case .deviceChanged: "Core Audio reassigned the selected device ID. The output was stopped."
            case .deviceMonitoringUnavailable: "The selected output device cannot be monitored for disconnection."
            case .outputUnitUnavailable: "The Core Audio HAL output unit is unavailable."
            case let .audioStatus(status): "Core Audio output failed with status \(status)."
            }
        }
    }
}

private struct RouteRender {
    let key: String
    let channels: [Int]
    let render: CoreAudioOutputCoordinator.RenderHandler
}

private final class RouteSnapshot {
    let routes: [RouteRender]

    init(routes: [RouteRender]) {
        self.routes = routes
    }
}
