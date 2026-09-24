import Foundation

extension AppDelegate {
    func createRoute(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "name", "deviceUID", "mode", "channels"],
              let name = body["name"] as? String,
              let uid = body["deviceUID"] as? String, !uid.isEmpty,
              let mode = body["mode"] as? String,
              let channels = body["channels"] as? [Int]
        else { throw BridgeError.invalidPayload }
        let selection: BlackHoleChannels
        switch (mode, channels) {
        case let ("mono", values) where values.count == 1:
            selection = .mono(values[0])
        case let ("stereo", values) where values.count == 2:
            selection = .stereo(left: values[0], right: values[1])
        default: throw BridgeError.invalidPayload
        }
        let trimmedName = try validatedName(name)
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            guard let device = audioDevices.first(where: { $0.uid == uid }),
                  device.isAlive, device.outputChannels > 0,
                  device.name.localizedCaseInsensitiveContains("BlackHole")
            else { throw BridgeError.unavailableBlackHole }
            guard channels.allSatisfy({ $0 > 0 && $0 <= device.outputChannels }) else {
                throw BridgeError.invalidChannels
            }
            config.blackHoleRoutes.append(BlackHoleRoute(
                name: trimmedName, deviceUID: DeviceUID(rawValue: uid), channels: selection
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
            config.mutedSources.removeAll { $0 == source }
        }
    }
}
