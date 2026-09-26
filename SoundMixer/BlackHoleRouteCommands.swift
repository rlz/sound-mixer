import Foundation

extension AppDelegate {
    func createRoute(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "deviceUID"],
              let uid = body["deviceUID"] as? String, !uid.isEmpty
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            guard let device = audioDevices.first(where: { $0.uid == uid }),
                  device.isAlive, device.outputChannels > 0,
                  device.name.localizedCaseInsensitiveContains("BlackHole")
            else { throw BridgeError.unavailableBlackHole }
            guard !config.outputMixes.contains(where: { $0.deviceUID.rawValue == uid }) else {
                throw BridgeError.noBlackHoleChannels
            }
            let reserved = Set(config.blackHoleRoutes
                .filter { $0.deviceUID.rawValue == uid }
                .flatMap { Self.bridgeChannels($0.channels) })
            guard let first = stride(from: 1, through: max(0, device.outputChannels - 1), by: 2)
                .first(where: { !reserved.contains($0) && !reserved.contains($0 + 1) })
            else { throw BridgeError.noBlackHoleChannels }
            let second = first + 1
            config.blackHoleRoutes.append(BlackHoleRoute(
                name: "BlackHole \(first)/\(second)",
                deviceUID: DeviceUID(rawValue: uid),
                channels: .stereo(left: first, right: second)
            ))
        }
    }

    func deleteRoute(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id"],
              let idString = body["id"] as? String, let id = UUID(uuidString: idString)
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            guard config.blackHoleRoutes.contains(where: { $0.id == id }) else { throw BridgeError.unknownRoute }
            config.blackHoleRoutes.removeAll { $0.id == id }
            let source = SourceReference.blackHoleRoute(id)
            for index in config.outputMixes.indices {
                config.outputMixes[index].mix.inputs.removeAll { $0.source == source }
            }
            for index in config.buses.indices {
                config.buses[index].mix.inputs.removeAll { $0.source == source }
            }
            for index in config.blackHoleRoutes.indices {
                config.blackHoleRoutes[index].mix.inputs.removeAll { $0.source == source }
            }
            config.outputMixes.removeAll { $0.mix.inputs.isEmpty }
            config.mutedSources.removeAll { $0 == source }
            config.sourceLevels.removeAll { $0.source == source }
        }
    }
}
