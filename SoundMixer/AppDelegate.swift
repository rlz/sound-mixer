import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var configurationStore: ConfigurationStore?
    private var deviceCatalog: CoreAudioDeviceCatalog?
    private var processCatalog: CoreAudioProcessCatalog?
    private var captureCoordinator: AudioCaptureCoordinator?
    private var audioRoutingCoordinator: AudioRoutingCoordinator?
    private let audioControlQueue = DispatchQueue(label: "com.rlz.soundmixer.audio-control")
    private var meterTimer: DispatchSourceTimer?
    private var meterReadPending = false
    private var sourceLevels: [String: Double] = [:]
    private var inputChannelLevels: [String: [Double?]] = [:]
    private var renderLevels: [String: Double] = [:]
    var audioDevices: [AudioDeviceSnapshot] = []
    private var audioProcesses: [AudioProcessSnapshot] = []
    private var captureStates: [String: String] = [:]
    private var outputRouteErrors: [String: String] = [:]
    private var startupConfigurationWarning: String?

    func applicationDidFinishLaunching(_: Notification) {
        let configurationWarning = loadConfiguration()
        setupAudioServices()
        let (window, webView) = createWindow()
        self.window = window
        self.webView = webView
        guard loadInterface(in: webView, configurationWarning: configurationWarning) else {
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadConfiguration() -> String? {
        do {
            let identifier = Bundle.main.bundleIdentifier ?? "com.rlz.soundmixer"
            let store = try ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL(bundleIdentifier: identifier))
            try store.update { configuration in
                for index in configuration.outputMixes.indices {
                    configuration.outputMixes[index].mix.level = 1
                }
            }
            configurationStore = store
            return store.discardedInvalidConfiguration
                ? "The invalid saved configuration was deleted. Sound Mixer started with empty settings and mixing off."
                : nil
        } catch {
            return "The saved configuration could not be reset, so mixing is unavailable. \(error.localizedDescription)"
        }
    }

    private func setupAudioServices() {
        let deviceCatalog = CoreAudioDeviceCatalog()
        deviceCatalog.onChange = { [weak self] devices in
            guard let self, audioDevices != devices else { return }
            let routingChanged = audioDevices.count != devices.count ||
                !zip(audioDevices, devices).allSatisfy { $0.hasSameRouting(as: $1) }
            audioDevices = devices
            if routingChanged {
                updateAudioRouting()
            }
            publishState()
        }
        self.deviceCatalog = deviceCatalog
        deviceCatalog.start()

        let processCatalog = CoreAudioProcessCatalog()
        processCatalog.onChange = { [weak self] processes in
            guard let self, audioProcesses != processes else { return }
            audioProcesses = processes
            updateAudioRouting()
            publishState()
        }
        self.processCatalog = processCatalog
        processCatalog.start()

        let captureCoordinator = AudioCaptureCoordinator()
        captureCoordinator.onStateChange = { [weak self] id, state in
            self?.captureStates[id] = Self.bridgeCaptureState(state)
            self?.publishState()
        }
        self.captureCoordinator = captureCoordinator
        let audioRoutingCoordinator = AudioRoutingCoordinator(capture: captureCoordinator)
        audioRoutingCoordinator.onRoutingReset = { [weak self] in
            DispatchQueue.main.async {
                self?.outputRouteErrors.removeAll()
                self?.sourceLevels.removeAll()
                self?.inputChannelLevels.removeAll()
                self?.renderLevels.removeAll()
                self?.publishState()
            }
        }
        audioRoutingCoordinator.onRouteError = { [weak self] route, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if route.hasPrefix("output:") {
                    let uid = String(route.dropFirst("output:".count))
                    self.outputRouteErrors[uid] = error
                }
                self.publishState()
            }
        }
        self.audioRoutingCoordinator = audioRoutingCoordinator
        updateAudioRouting()
        startMeterTimer()
    }

    private func startMeterTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(67), leeway: .milliseconds(8))
        timer.setEventHandler { [weak self] in self?.refreshMeterReadings() }
        timer.resume()
        meterTimer = timer
    }

    private static func bridgeCaptureState(_ state: AudioCaptureState) -> String {
        switch state {
        case .stopped: "stopped"
        case .starting: "starting"
        case .capturing: "capturing"
        case .permissionDenied: "permissionDenied"
        case let .unavailable(reason): "unavailable: \(reason)"
        }
    }

    private func createWindow() -> (NSWindow, WKWebView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sound Mixer"
        window.center()
        window.minSize = NSSize(width: 760, height: 500)

        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(self, name: "soundMixer")
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        return (window, webView)
    }

    private func loadInterface(in webView: WKWebView, configurationWarning: String?) -> Bool {
        guard let webDirectory = Bundle.main.url(forResource: "dist", withExtension: nil),
              let indexURL = URL(string: "index.html", relativeTo: webDirectory)
        else {
            showLoadError("The local interface was not found in the app bundle.")
            return false
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)
        startupConfigurationWarning = configurationWarning
        return true
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        if let warning = startupConfigurationWarning {
            startupConfigurationWarning = nil
            showLoadError(warning)
        }
        publishState()
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        meterTimer?.cancel()
        meterTimer = nil
        let routingCoordinator = audioRoutingCoordinator
        audioControlQueue.sync {
            routingCoordinator?.stop()
            if routingCoordinator == nil {
                captureCoordinator?.stopAll()
            }
        }
        deviceCatalog?.stop()
        processCatalog?.stop()
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        showLoadError("Could not open the local interface: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        showLoadError("Could not load the local interface: \(error.localizedDescription)")
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "soundMixer", let body = message.body as? [String: Any],
              let requestID = body["requestId"] as? String,
              let command = body["command"] as? String
        else { return }
        guard !requestID.isEmpty, requestID.count <= 128 else { return }

        do {
            if command == "ready" {
                try handleReady(body: body, requestID: requestID)
                return
            }
            if command == "openPrivacySettings" {
                guard Set(body.keys) == ["requestId", "command"] else { throw BridgeError.invalidPayload }
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(settingsURL)
                }
                sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
                return
            }
            if command == "setDeviceVolume" {
                try setDeviceVolume(body: body, requestID: requestID)
                return
            }
            let configuration = try executeCommand(command, body: body)
            sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
            updateAudioRouting()
            publishState(configuration: configuration)
        } catch {
            sendToWeb(method: "onCommandResult", payload: [
                "requestId": requestID,
                "accepted": false,
                "error": error.localizedDescription
            ])
        }
    }

    private func handleReady(body: [String: Any], requestID: String) throws {
        guard Set(body.keys) == ["requestId", "command"] else { throw BridgeError.invalidPayload }
        sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
        publishState()
    }

    private func executeCommand(_ command: String, body: [String: Any]) throws -> MixerConfiguration {
        guard let store = configurationStore else { throw BridgeError.storageUnavailable }
        switch command {
        case "setMasterEnabled": return try updateMixingEnabled(body: body, store: store)
        case "setVirtualMixLevel": return try setVirtualMixLevel(body: body, store: store)
        case "deleteOutputMix": return try deleteOutputMix(body: body, store: store)
        case "setSourceMuted": return try setSourceMuted(body: body, store: store)
        case "createBus": return try createBus(body: body, store: store)
        case "renameBus": return try renameBus(body: body, store: store)
        case "renameRoute": return try renameRoute(body: body, store: store)
        case "createRoute": return try createRoute(body: body, store: store)
        case "deleteBus": return try deleteBus(body: body, store: store)
        case "deleteRoute": return try deleteRoute(body: body, store: store)
        case "addMixInput": return try editMixInput(body: body, store: store, operation: .add)
        case "removeMixInput": return try editMixInput(body: body, store: store, operation: .remove)
        case "setMixInputLevel": return try editMixInput(body: body, store: store, operation: .level)
        case "setMonoPlacement": return try editMixInput(body: body, store: store, operation: .placement)
        case "setPhysicalInputChannels": return try setPhysicalInputChannels(body: body, store: store)
        default:
            throw BridgeError.unknownCommand
        }
    }

    private func updateMixingEnabled(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "enabled"], let enabled = body["enabled"] as? Bool
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { $0.isEnabled = enabled }
    }

    private func setDeviceVolume(body: [String: Any], requestID: String) throws {
        guard Set(body.keys) == ["requestId", "command", "uid", "level"],
              let uid = body["uid"] as? String, !uid.isEmpty,
              let level = body["level"] as? Double, level.isFinite, (0 ... 1).contains(level),
              let deviceCatalog else { throw BridgeError.invalidPayload }
        deviceCatalog.setOutputVolume(uid: uid, level: level) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
            case let .failure(error):
                sendToWeb(method: "onCommandResult", payload: [
                    "requestId": requestID, "accepted": false, "error": error.localizedDescription
                ])
            }
        }
    }

    private func deleteOutputMix(
        body: [String: Any], store: ConfigurationStore
    ) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "uid"],
              let uid = body["uid"] as? String, !uid.isEmpty
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard candidate.outputMixes.contains(where: { $0.deviceUID.rawValue == uid }) else {
                throw BridgeError.unknownOutput
            }
            candidate.outputMixes.removeAll { $0.deviceUID.rawValue == uid }
        }
    }

    private func setSourceMuted(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "kind", "sourceID", "muted"],
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty,
              let muted = body["muted"] as? Bool else { throw BridgeError.invalidPayload }
        let source: SourceReference
        switch kind {
        case "inputDevice": source = .inputDevice(DeviceUID(rawValue: sourceID))
        case "application": source = .application(ApplicationID(rawValue: sourceID))
        case "blackHoleRoute":
            guard let routeID = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            source = .blackHoleRoute(routeID)
        default: throw BridgeError.invalidPayload
        }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            config.mutedSources.removeAll { $0 == source }
            if muted {
                config.mutedSources.append(source)
            }
        }
    }

    private func createBus(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "name"], let name = body["name"] as? String
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            try candidate.buses.append(VirtualBus(name: validatedName(name)))
        }
    }

    private func renameBus(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id", "name"],
              let idString = body["id"] as? String, let id = UUID(uuidString: idString),
              let name = body["name"] as? String
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard let index = candidate.buses.firstIndex(where: { $0.id == id }) else { throw BridgeError.unknownBus }
            candidate.buses[index].name = try validatedName(name)
        }
    }

    private func deleteBus(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id"],
              let idString = body["id"] as? String, let id = UUID(uuidString: idString)
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard candidate.buses.contains(where: { $0.id == id }) else { throw BridgeError.unknownBus }
            candidate.buses.removeAll { $0.id == id }
        }
    }

    private func renameRoute(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id", "name"],
              let idString = body["id"] as? String, let id = UUID(uuidString: idString),
              let name = body["name"] as? String
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard let index = candidate.blackHoleRoutes.firstIndex(where: { $0.id == id }) else {
                throw BridgeError.unknownRoute
            }
            candidate.blackHoleRoutes[index].name = try validatedName(name)
        }
    }

    private func setVirtualMixLevel(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "target", "id", "level"],
              let target = body["target"] as? String, ["bus", "route"].contains(target),
              let idString = body["id"] as? String, let id = UUID(uuidString: idString),
              let level = body["level"] as? Double, level.isFinite, (0 ... 1).contains(level)
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            if target == "bus" {
                guard let index = candidate.buses.firstIndex(where: { $0.id == id }) else { throw BridgeError.unknownBus }
                candidate.buses[index].mix.level = level
            } else {
                guard let index = candidate.blackHoleRoutes.firstIndex(where: { $0.id == id }) else { throw BridgeError.unknownRoute }
                candidate.blackHoleRoutes[index].mix.level = level
            }
        }
    }

    private enum MixInputOperation: Equatable { case add, remove, level, placement }

    private func editMixInput(body: [String: Any], store: ConfigurationStore, operation: MixInputOperation) throws -> MixerConfiguration {
        let common: Set = ["requestId", "command", "target", "id", "kind", "sourceID"]
        let expected = common.union(operation == .add ? ["monoPlacement"] : (operation == .level ? ["level"] : (operation == .placement ? ["monoPlacement"] : [])))
        guard Set(body.keys) == expected,
              let target = body["target"] as? String, ["output", "bus", "route"].contains(target),
              let id = body["id"] as? String, !id.isEmpty,
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty
        else { throw BridgeError.invalidPayload }
        let reference: SourceReference
        switch kind {
        case "inputDevice": reference = .inputDevice(DeviceUID(rawValue: sourceID))
        case "application": reference = .application(ApplicationID(rawValue: sourceID))
        case "bus":
            guard let busID = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            reference = .bus(busID)
        case "blackHoleRoute":
            guard let routeID = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            reference = .blackHoleRoute(routeID)
        default: throw BridgeError.invalidPayload
        }
        let level = body["level"] as? Double
        let placement = (body["monoPlacement"] as? String).flatMap(MonoPlacement.init(rawValue:))
        if operation == .level {
            let maximum = kind == "application" ? MixInput.maximumApplicationGain : 1
            guard let level, level.isFinite, (0 ... maximum).contains(level) else {
                throw BridgeError.invalidPayload
            }
        }
        if operation == .add || operation == .placement, placement == nil {
            throw BridgeError.invalidPayload
        }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            switch target {
            case "output":
                let index: Int
                if let existingIndex = config.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == id }) {
                    index = existingIndex
                } else {
                    guard operation == .add,
                          let device = audioDevices.first(where: { $0.uid == id }),
                          device.isAlive, device.outputChannels > 0
                    else { throw BridgeError.unknownOutput }
                    config.outputMixes.append(OutputMix(deviceUID: DeviceUID(rawValue: id)))
                    index = config.outputMixes.count - 1
                }
                var value = config.outputMixes[index].mix
                try applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.outputMixes[index].mix = value
            case "bus":
                guard let uuid = UUID(uuidString: id), let index = config.buses.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownBus }
                var value = config.buses[index].mix
                try applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.buses[index].mix = value
            default:
                guard let uuid = UUID(uuidString: id), let index = config.blackHoleRoutes.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownRoute }
                var value = config.blackHoleRoutes[index].mix
                try applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.blackHoleRoutes[index].mix = value
            }
        }
    }

    private func applyInput(_ operation: MixInputOperation, reference: SourceReference, level: Double?, placement: MonoPlacement?, to mix: inout Mix) throws {
        switch operation {
        case .add:
            guard !mix.inputs.contains(where: { $0.source == reference }), let placement else { throw BridgeError.invalidPayload }
            if case let .inputDevice(uid) = reference,
               let device = audioDevices.first(where: { $0.uid == uid.rawValue })
            {
                let defaults = MixInput.physicalInputDefaults(channelCount: device.inputChannels, mono: device.inputChannels == 1)
                mix.inputs.append(MixInput(source: reference, monoPlacement: placement,
                                           channelRouting: defaults.routing, channelLevels: defaults.levels))
            } else {
                mix.inputs.append(MixInput(source: reference, monoPlacement: placement))
            }
        case .remove:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }) else { throw BridgeError.invalidPayload }
            mix.inputs.remove(at: index)
        case .level:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }), let level else { throw BridgeError.invalidPayload }
            mix.inputs[index].level = level
        case .placement:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }), let placement else { throw BridgeError.invalidPayload }
            mix.inputs[index].monoPlacement = placement
        }
    }

    private func setPhysicalInputChannels(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        let expected: Set = ["requestId", "command", "target", "id", "sourceID", "channelRouting", "channelLevels", "channelsLinked"]
        guard Set(body.keys) == expected,
              let target = body["target"] as? String, ["output", "bus", "route"].contains(target),
              let id = body["id"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty,
              let routingValues = body["channelRouting"] as? [String],
              let routing = Optional(routingValues.compactMap { ChannelRouting(rawValue: $0) }), routing.count == routingValues.count,
              let levels = body["channelLevels"] as? [Double], levels.count == routing.count,
              levels.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }),
              let linked = body["channelsLinked"] as? Bool
        else { throw BridgeError.invalidPayload }
        let reference = SourceReference.inputDevice(DeviceUID(rawValue: sourceID))
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            var mix: Mix
            switch target {
            case "output":
                guard let index = config.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == id }) else { throw BridgeError.unknownOutput }
                mix = config.outputMixes[index].mix
                try Self.assignChannels(reference, routing, levels, linked, to: &mix)
                config.outputMixes[index].mix = mix
            case "bus":
                guard let uuid = UUID(uuidString: id), let index = config.buses.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownBus }
                mix = config.buses[index].mix
                try Self.assignChannels(reference, routing, levels, linked, to: &mix)
                config.buses[index].mix = mix
            default:
                guard let uuid = UUID(uuidString: id), let index = config.blackHoleRoutes.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownRoute }
                mix = config.blackHoleRoutes[index].mix
                try Self.assignChannels(reference, routing, levels, linked, to: &mix)
                config.blackHoleRoutes[index].mix = mix
            }
        }
    }

    private static func assignChannels(_ reference: SourceReference, _ routing: [ChannelRouting], _ levels: [Double], _ linked: Bool, to mix: inout Mix) throws {
        guard let index = mix.inputs.firstIndex(where: { $0.source == reference }) else { throw BridgeError.invalidPayload }
        mix.inputs[index].channelRouting = routing
        mix.inputs[index].channelLevels = levels
        mix.inputs[index].channelsLinked = linked
    }

    func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { throw BridgeError.invalidName }
        return trimmed
    }
}

extension AppDelegate {
    func discoveredDescriptors() -> [AudioDeviceDescriptor] {
        audioDevices.map {
            AudioDeviceDescriptor(
                uid: DeviceUID(rawValue: $0.uid), name: $0.name, inputChannels: $0.inputChannels,
                outputChannels: $0.outputChannels, sampleRate: $0.nominalSampleRate,
                isBlackHole: $0.name.localizedCaseInsensitiveContains("BlackHole")
            )
        }
    }

    func updateAudioRouting() {
        guard let graph = configurationStore?.activeGraph,
              let coordinator = audioRoutingCoordinator
        else { return }
        let devices = audioDevices
        let processes = audioProcesses
        audioControlQueue.async { [weak self] in
            if coordinator.update(graph: graph, devices: devices, processes: processes) {
                DispatchQueue.main.async { self?.publishState() }
            }
        }
    }

    private func refreshMeterReadings() {
        guard !meterReadPending, let coordinator = audioRoutingCoordinator else { return }
        meterReadPending = true
        audioControlQueue.async { [weak self] in
            let sourceLevels = coordinator.sourceLevelReadings()
            let inputChannelLevels = coordinator.inputChannelLevelReadings()
            let renderLevels = coordinator.renderLevelReadings()
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceLevels = sourceLevels
                self.inputChannelLevels = inputChannelLevels
                self.renderLevels = renderLevels
                self.meterReadPending = false
                self.publishState()
            }
        }
    }

    func publishState(configuration: MixerConfiguration? = nil) {
        guard let configuration = configuration ?? configurationStore?.configuration else { return }
        let discovered = Dictionary(uniqueKeysWithValues: audioDevices.map { ($0.uid, $0) })
        let state = BridgeState(
            schemaVersion: MixerConfiguration.currentSchemaVersion,
            isEnabled: configuration.isEnabled,
            devices: bridgeDevices(configuration: configuration, discovered: discovered),
            outputs: bridgeOutputs(configuration: configuration, discovered: discovered, renderLevels: renderLevels),
            buses: configuration.buses.map { BridgeNamedItem(id: $0.id.uuidString, name: $0.name) },
            blackHoleRoutes: configuration.blackHoleRoutes.map { route in
                let device = discovered[route.deviceUID.rawValue]
                let selected = Self.bridgeChannels(route.channels)
                let pairAvailable = device.map {
                    $0.isAlive && selected.count == 2 && $0.inputChannels >= (selected.max() ?? Int.max)
                } ?? false
                return BridgeRoute(
                    id: route.id.uuidString, name: route.name, deviceUID: route.deviceUID.rawValue,
                    channels: selected, available: pairAvailable,
                    captureState: captureStates["route:\(route.id.uuidString)"] ?? (pairAvailable ? "stopped" : "unavailable"),
                    level: sourceLevels["route:\(route.id.uuidString)"],
                    muted: configuration.mutedSources.contains(.blackHoleRoute(route.id))
                )
            },
            applications: bridgeApplications(configuration: configuration, sourceLevels: sourceLevels),
            inputCaptureStates: captureStates.filter { id, _ in audioDevices.contains(where: { $0.uid == id }) }
                .map {
                    BridgeInputCaptureState(
                        uid: $0.key,
                        state: $0.value,
                        level: sourceLevels["input:\($0.key)"],
                        channelLevels: inputChannelLevels["input:\($0.key)"] ?? []
                    )
                },
            mixes: bridgeMixes(configuration, renderLevels: renderLevels)
        )
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.soundMixerBridge?.onState(\(json))")
    }

    func bridgeMixes(_ configuration: MixerConfiguration, renderLevels: [String: Double] = [:]) -> [BridgeMix] {
        func item(_ target: String, _ id: String, _ mix: Mix) -> BridgeMix {
            let targetKey = "\(target == "output" ? "output" : target):\(id)"
            let inputs = mix.inputs.map { input -> BridgeMixInput in
                let kind: String
                let sourceID: String
                switch input.source {
                case let .inputDevice(uid): kind = "inputDevice"; sourceID = uid.rawValue
                case let .application(app): kind = "application"; sourceID = app.rawValue
                case let .bus(bus): kind = "bus"; sourceID = bus.uuidString
                case let .blackHoleRoute(route): kind = "blackHoleRoute"; sourceID = route.uuidString
                }
                return BridgeMixInput(
                    kind: kind,
                    id: sourceID,
                    level: input.level,
                    monoPlacement: input.monoPlacement.rawValue,
                    channelRouting: input.channelRouting.map(\.rawValue),
                    channelLevels: input.channelLevels,
                    channelsLinked: input.channelsLinked,
                    levelReading: renderLevels["\(targetKey)/\(AudioGraphRenderer.sourceMeterKey(input.source))"]
                )
            }
            return BridgeMix(
                target: target,
                id: id,
                level: mix.level,
                inputs: inputs,
                levelReading: renderLevels["\(targetKey)/destination"]
            )
        }
        return configuration.outputMixes.map { item("output", $0.deviceUID.rawValue, $0.mix) }
            + configuration.buses.map { item("bus", $0.id.uuidString, $0.mix) }
            + configuration.blackHoleRoutes.map { item("route", $0.id.uuidString, $0.mix) }
    }

    func bridgeApplications(configuration: MixerConfiguration, sourceLevels: [String: Double]) -> [BridgeApplication] {
        let configuredIDs = (configuration.outputMixes.map(\.mix)
            + configuration.buses.map(\.mix)
            + configuration.blackHoleRoutes.map(\.mix))
            .flatMap(\.inputs)
            .compactMap { input -> String? in
                guard case let .application(id) = input.source else { return nil }
                return id.rawValue
            }
        let orderedProcesses = audioProcesses.sorted {
            if $0.applicationID != $1.applicationID {
                return $0.applicationID < $1.applicationID
            }
            if $0.isProducingOutput != $1.isProducingOutput {
                return $0.isProducingOutput
            }
            return $0.processID < $1.processID
        }
        let processes = Dictionary(
            orderedProcesses.map { ($0.applicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return Set(configuredIDs).union(processes.keys).sorted().map { id in
            let process = processes[id]
            return BridgeApplication(
                id: id,
                name: process?.name ?? id,
                available: process?.isProducingOutput ?? false,
                captureState: captureStates[id] ?? "stopped",
                muted: configuration.mutedSources.contains(.application(ApplicationID(rawValue: id))),
                level: sourceLevels["application:\(id)"]
            )
        }
    }

    static func bridgeChannels(_ channels: BlackHoleChannels) -> [Int] {
        switch channels {
        case let .mono(channel): [channel]
        case let .stereo(left, right): [left, right]
        }
    }

    func bridgeDevices(configuration: MixerConfiguration, discovered: [String: AudioDeviceSnapshot]) -> [BridgeDevice] {
        let savedUIDs = configuration.knownDevices.map(\.uid.rawValue)
        let deviceUIDs = Set(discovered.keys).union(savedUIDs).sorted()
        return deviceUIDs.map { uid -> BridgeDevice in
            let live = discovered[uid]
            let deviceUID = DeviceUID(rawValue: uid)
            var savedAs: [String] = []
            if configuration.outputMixes.contains(where: { $0.deviceUID == deviceUID }) {
                savedAs.append("output")
            }
            if configuration.blackHoleRoutes.contains(where: { $0.deviceUID == deviceUID }) {
                savedAs.append("blackHoleRoute")
            }
            let mixes = configuration.outputMixes.map(\.mix) + configuration.buses.map(\.mix) + configuration.blackHoleRoutes.map(\.mix)
            let isSavedInput = mixes.flatMap(\.inputs).contains { input in
                if case let .inputDevice(inputUID) = input.source {
                    return inputUID == deviceUID
                }
                return false
            }
            if isSavedInput {
                savedAs.append("input")
            }
            return BridgeDevice(
                uid: uid,
                name: live?.name ?? configuration.deviceDisplayName(for: deviceUID),
                discovered: live != nil,
                available: live.map(\.isAlive) ?? false,
                inputChannels: live?.inputChannels ?? 0,
                outputChannels: live?.outputChannels ?? 0,
                savedAs: savedAs,
                muted: configuration.mutedSources.contains(.inputDevice(deviceUID))
            )
        }
    }

    func bridgeOutputs(configuration: MixerConfiguration, discovered: [String: AudioDeviceSnapshot], renderLevels: [String: Double] = [:]) -> [BridgeOutput] {
        let saved = Dictionary(uniqueKeysWithValues: configuration.outputMixes.map { ($0.deviceUID.rawValue, $0) })
        let discoveredOutputUIDs = audioDevices.filter { $0.outputChannels > 0 }.map(\.uid)
        return Set(discoveredOutputUIDs).union(saved.keys).sorted().map { uid -> BridgeOutput in
            let live = discovered[uid]
            return BridgeOutput(
                uid: uid,
                name: live?.name ?? configuration.deviceDisplayName(for: DeviceUID(rawValue: uid)),
                isBlackHole: (live?.name ?? configuration.deviceDisplayName(for: DeviceUID(rawValue: uid)))
                    .localizedCaseInsensitiveContains("BlackHole"),
                available: live.map { $0.isAlive && $0.outputChannels > 0 } ?? false,
                outputChannels: live?.outputChannels ?? 0,
                volume: live?.outputVolume,
                volumeWritable: live?.canSetOutputVolume ?? false,
                configured: saved[uid] != nil,
                routeError: outputRouteErrors[uid],
                levelReading: renderLevels["output:\(uid)/destination"]
            )
        }
    }

    func sendToWeb(method: String, payload: [String: Any]) {
        guard let webView, JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.soundMixerBridge?.\(method)(\(json))")
    }

    func showLoadError(_ message: String) {
        guard let webView else { return }
        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.frame = webView.bounds.insetBy(dx: 32, dy: 32)
        label.autoresizingMask = [.width, .height]
        webView.addSubview(label)
    }
}
