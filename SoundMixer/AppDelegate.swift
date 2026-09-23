import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var configurationStore: ConfigurationStore?
    private var deviceCatalog: CoreAudioDeviceCatalog?
    private var processCatalog: CoreAudioProcessCatalog?
    private var captureCoordinator: AudioCaptureCoordinator?
    private var audioRoutingCoordinator: AudioRoutingCoordinator?
    private var audioDevices: [AudioDeviceSnapshot] = []
    private var audioProcesses: [AudioProcessSnapshot] = []
    private var captureStates: [String: String] = [:]
    private var outputRouteErrors: [String: String] = [:]

    func applicationDidFinishLaunching(_: Notification) {
        let configurationFailed = !loadConfiguration()
        setupAudioServices()
        let (window, webView) = createWindow()
        self.window = window
        self.webView = webView
        guard loadInterface(in: webView, configurationFailed: configurationFailed) else {
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadConfiguration() -> Bool {
        do {
            let identifier = Bundle.main.bundleIdentifier ?? "com.rlz.soundmixer"
            configurationStore = try ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL(bundleIdentifier: identifier))
            return true
        } catch {
            return false
        }
    }

    private func setupAudioServices() {
        let deviceCatalog = CoreAudioDeviceCatalog()
        deviceCatalog.onChange = { [weak self] devices in
            self?.audioDevices = devices
            self?.updateAudioRouting()
            self?.publishState()
        }
        self.deviceCatalog = deviceCatalog
        deviceCatalog.start()

        let processCatalog = CoreAudioProcessCatalog()
        processCatalog.onChange = { [weak self] processes in
            self?.audioProcesses = processes
            self?.updateAudioRouting()
            self?.publishState()
        }
        self.processCatalog = processCatalog
        processCatalog.start()

        let captureCoordinator = AudioCaptureCoordinator()
        captureCoordinator.onStateChange = { [weak self] id, state in
            self?.captureStates[id] = String(describing: state)
            self?.publishState()
        }
        self.captureCoordinator = captureCoordinator
        let audioRoutingCoordinator = AudioRoutingCoordinator(capture: captureCoordinator)
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
        webView.configuration.userContentController.add(self, name: "soundMixer")
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        return (window, webView)
    }

    private func loadInterface(in webView: WKWebView, configurationFailed: Bool) -> Bool {
        guard let webDirectory = Bundle.main.url(forResource: "dist", withExtension: nil),
              let indexURL = URL(string: "index.html", relativeTo: webDirectory)
        else {
            showLoadError("The local interface was not found in the app bundle.")
            return false
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)
        if configurationFailed {
            showLoadError(
                "The saved configuration could not be loaded. Mixing is off and the file was preserved. " +
                    "Check or repair the configuration before editing."
            )
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        deviceCatalog?.stop()
        processCatalog?.stop()
        audioRoutingCoordinator?.stop()
        captureCoordinator?.stopAll()
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        showLoadError("Could not open the local interface: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        showLoadError("Could not load the local interface: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        publishState()
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
        case "setOutputLevel": return try setOutputLevel(body: body, store: store)
        case "createBus": return try createBus(body: body, store: store)
        case "renameBus": return try renameBus(body: body, store: store)
        case "renameRoute": return try renameRoute(body: body, store: store)
        case "deleteBus": return try deleteBus(body: body, store: store)
        case "addMixInput": return try editMixInput(body: body, store: store, operation: .add)
        case "removeMixInput": return try editMixInput(body: body, store: store, operation: .remove)
        case "setMixInputLevel": return try editMixInput(body: body, store: store, operation: .level)
        case "setMonoPlacement": return try editMixInput(body: body, store: store, operation: .placement)
        default:
            throw BridgeError.unknownCommand
        }
    }

    private func updateMixingEnabled(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "enabled"], let enabled = body["enabled"] as? Bool
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { $0.isEnabled = enabled }
    }

    private func setOutputLevel(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "uid", "level"],
              let uid = body["uid"] as? String, !uid.isEmpty,
              let level = body["level"] as? Double, (0 ... 1).contains(level)
        else { throw BridgeError.invalidPayload }
        return try updateOutputLevel(store: store, uid: uid, level: level)
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

    private func updateOutputLevel(store: ConfigurationStore, uid: String, level: Double) throws -> MixerConfiguration {
        try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard let index = candidate.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == uid }) else {
                throw BridgeError.unknownOutput
            }
            candidate.outputMixes[index].mix.level = level
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
        default: throw BridgeError.invalidPayload
        }
        let level = body["level"] as? Double
        let placement = (body["monoPlacement"] as? String).flatMap(MonoPlacement.init(rawValue:))
        if operation == .level, level == nil || !(0 ... 1).contains(level!) {
            throw BridgeError.invalidPayload
        }
        if operation == .add || operation == .placement, placement == nil {
            throw BridgeError.invalidPayload
        }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            switch target {
            case "output":
                guard let index = config.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == id }) else { throw BridgeError.unknownOutput }
                var value = config.outputMixes[index].mix
                try Self.applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.outputMixes[index].mix = value
            case "bus":
                guard let uuid = UUID(uuidString: id), let index = config.buses.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownBus }
                var value = config.buses[index].mix
                try Self.applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.buses[index].mix = value
            default:
                guard let uuid = UUID(uuidString: id), let index = config.blackHoleRoutes.firstIndex(where: { $0.id == uuid }) else { throw BridgeError.unknownRoute }
                var value = config.blackHoleRoutes[index].mix
                try Self.applyInput(operation, reference: reference, level: level, placement: placement, to: &value)
                config.blackHoleRoutes[index].mix = value
            }
        }
    }

    private static func applyInput(_ operation: MixInputOperation, reference: SourceReference, level: Double?, placement: MonoPlacement?, to mix: inout Mix) throws {
        switch operation {
        case .add:
            guard !mix.inputs.contains(where: { $0.source == reference }), let placement else { throw BridgeError.invalidPayload }
            mix.inputs.append(MixInput(source: reference, monoPlacement: placement))
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

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { throw BridgeError.invalidName }
        return trimmed
    }
}

private extension AppDelegate {
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
        guard let graph = configurationStore?.activeGraph else { return }
        if audioRoutingCoordinator?.update(graph: graph, devices: audioDevices, processes: audioProcesses) == true {
            outputRouteErrors.removeAll()
        }
    }

    func publishState(configuration: MixerConfiguration? = nil) {
        guard let configuration = configuration ?? configurationStore?.configuration else { return }
        let discovered = Dictionary(uniqueKeysWithValues: audioDevices.map { ($0.uid, $0) })
        let state = BridgeState(
            schemaVersion: MixerConfiguration.currentSchemaVersion,
            isEnabled: configuration.isEnabled,
            devices: bridgeDevices(configuration: configuration, discovered: discovered),
            outputs: bridgeOutputs(configuration: configuration, discovered: discovered),
            buses: configuration.buses.map { BridgeNamedItem(id: $0.id.uuidString, name: $0.name) },
            blackHoleRoutes: configuration.blackHoleRoutes.map {
                BridgeRoute(id: $0.id.uuidString, name: $0.name, deviceUID: $0.deviceUID.rawValue)
            },
            applications: audioProcesses.map {
                BridgeApplication(
                    id: $0.applicationID,
                    name: $0.name,
                    available: $0.isProducingOutput,
                    captureState: captureStates[$0.applicationID] ?? "stopped"
                )
            },
            inputCaptureStates: captureStates.filter { id, _ in audioDevices.contains(where: { $0.uid == id }) }
                .map { BridgeInputCaptureState(uid: $0.key, state: $0.value) },
            mixes: bridgeMixes(configuration)
        )
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.soundMixerBridge?.onState(\(json))")
    }

    func bridgeMixes(_ configuration: MixerConfiguration) -> [BridgeMix] {
        func item(_ target: String, _ id: String, _ mix: Mix) -> BridgeMix {
            BridgeMix(target: target, id: id, level: mix.level, inputs: mix.inputs.map { input in
                let kind: String
                let sourceID: String
                switch input.source {
                case let .inputDevice(uid): kind = "inputDevice"; sourceID = uid.rawValue
                case let .application(app): kind = "application"; sourceID = app.rawValue
                case let .bus(bus): kind = "bus"; sourceID = bus.uuidString
                }
                return BridgeMixInput(kind: kind, id: sourceID, level: input.level, monoPlacement: input.monoPlacement.rawValue)
            })
        }
        return configuration.outputMixes.map { item("output", $0.deviceUID.rawValue, $0.mix) }
            + configuration.buses.map { item("bus", $0.id.uuidString, $0.mix) }
            + configuration.blackHoleRoutes.map { item("route", $0.id.uuidString, $0.mix) }
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
                savedAs: savedAs
            )
        }
    }

    func bridgeOutputs(configuration: MixerConfiguration, discovered: [String: AudioDeviceSnapshot]) -> [BridgeOutput] {
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
                level: saved[uid]?.mix.level ?? 1,
                configured: saved[uid] != nil,
                routeError: outputRouteErrors[uid]
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
