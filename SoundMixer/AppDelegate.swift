import AppKit
import WebKit

// The bridge command handlers remain together until they can be split without changing validation behavior.
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
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
    private var deviceLevels: [String: Double] = [:]
    var audioDevices: [AudioDeviceSnapshot] = []
    private var audioProcesses: [AudioProcessSnapshot] = []
    private var captureStates: [String: String] = [:]
    private var outputRouteErrors: [String: String] = [:]
    private var startupConfigurationWarning: String?
    private var startupConfigurationWarningIsError = false

    func applicationDidFinishLaunching(_: Notification) {
        setupEditMenu()
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

    private func setupEditMenu() {
        let menu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func loadConfiguration() -> String? {
        do {
            let identifier = Bundle.main.bundleIdentifier ?? "com.rlz.soundmixer"
            let store = try ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL(bundleIdentifier: identifier))
            try store.update { configuration in
                configuration.outputMixes.removeAll { $0.mix.inputs.isEmpty }
                for index in configuration.outputMixes.indices {
                    configuration.outputMixes[index].mix.level = 1
                }
            }
            configurationStore = store
            return store.discardedInvalidConfiguration
                ? "The invalid saved configuration was deleted. Sound Mixer started with empty settings and mixing off."
                : nil
        } catch {
            startupConfigurationWarningIsError = true
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
        configureRoutingCallbacks(audioRoutingCoordinator)
        self.audioRoutingCoordinator = audioRoutingCoordinator
        updateAudioRouting()
        startMeterTimer()
    }

    private func configureRoutingCallbacks(_ audioRoutingCoordinator: AudioRoutingCoordinator) {
        audioRoutingCoordinator.onRoutingReset = { [weak self] in
            DispatchQueue.main.async {
                self?.outputRouteErrors.removeAll()
                self?.sourceLevels.removeAll()
                self?.inputChannelLevels.removeAll()
                self?.renderLevels.removeAll()
                self?.deviceLevels.removeAll()
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
        case .idle: "idle"
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
        #if DEBUG
            webView.isInspectable = true
        #endif
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
            if startupConfigurationWarningIsError {
                showLoadError(warning)
            } else {
                sendToWeb(method: "onNotification", payload: ["message": warning])
            }
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
            if command == "setDeviceMuted" {
                try setDeviceMuted(body: body, requestID: requestID)
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

    // This switch is an exhaustive command dispatch table.
    // swiftlint:disable:next cyclomatic_complexity
    private func executeCommand(_ command: String, body: [String: Any]) throws -> MixerConfiguration {
        guard let store = configurationStore else { throw BridgeError.storageUnavailable }
        switch command {
        case "setMasterEnabled": return try updateMixingEnabled(body: body, store: store)
        case "setDeviceHidden": return try setDeviceHidden(body: body, store: store)
        case "setVirtualMixLevel": return try setVirtualMixLevel(body: body, store: store)
        case "deleteOutputMix": return try deleteOutputMix(body: body, store: store)
        case "resetMix": return try resetMix(body: body, store: store)
        case "setSourceMuted": return try setSourceMuted(body: body, store: store)
        case "setSourceLevel": return try setSourceLevel(body: body, store: store)
        case "setBusMuted": return try setBusMuted(body: body, store: store)
        case "setBusChannelCount": return try setBusChannelCount(body: body, store: store)
        case "createBus": return try createBus(body: body, store: store)
        case "renameBus": return try renameBus(body: body, store: store)
        case "deleteBus": return try deleteBus(body: body, store: store)
        case "addMixInput": return try editMixInput(body: body, store: store, operation: .add)
        case "addApplicationInput": return try addApplicationInput(body: body, store: store)
        case "removeApplicationInput": return try removeApplicationInput(body: body, store: store)
        case "removeInputDevice": return try removeInputDevice(body: body, store: store)
        case "removeMixInput": return try editMixInput(body: body, store: store, operation: .remove)
        case "setMixInputLevel": return try editMixInput(body: body, store: store, operation: .level)
        case "setMixInputMuted": return try editMixInput(body: body, store: store, operation: .muted)
        case "setMixInputRouting": return try setMixInputRouting(body: body, store: store)
        case "setMixInputChannels": return try setMixInputChannels(body: body, store: store)
        default:
            throw BridgeError.unknownCommand
        }
    }

    private func addApplicationInput(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "applicationID"],
              let id = body["applicationID"] as? String, !id.isEmpty,
              audioProcesses.contains(where: { $0.applicationID == id && $0.isProducingOutput })
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            let applicationID = ApplicationID(rawValue: id)
            if !config.applications.contains(applicationID) {
                config.applications.append(applicationID)
            }
        }
    }

    private func removeApplicationInput(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "applicationID"],
              let id = body["applicationID"] as? String, !id.isEmpty
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            let applicationID = ApplicationID(rawValue: id)
            guard config.applications.contains(applicationID) else { throw BridgeError.invalidPayload }
            let source = SourceReference.application(applicationID)
            config.applications.removeAll { $0 == applicationID }
            config.outputMixes = config.outputMixes.map { output in
                var updated = output
                updated.mix.inputs.removeAll { $0.source == source }
                return updated
            }.filter { !$0.mix.inputs.isEmpty }
            config.buses = config.buses.map { bus in
                var updated = bus
                updated.mix.inputs.removeAll { $0.source == source }
                return updated
            }
            config.mutedSources.removeAll { $0 == source }
            config.sourceLevels.removeAll { $0.source == source }
        }
    }

    private func removeInputDevice(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "uid"],
              let uid = body["uid"] as? String, !uid.isEmpty
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            let deviceUID = DeviceUID(rawValue: uid)
            let source = SourceReference.inputDevice(deviceUID)
            let isConfigured = (config.outputMixes.map(\.mix) + config.buses.map(\.mix))
                .contains { mix in mix.inputs.contains { $0.source == source } }
            guard isConfigured else { throw BridgeError.invalidPayload }
            config.outputMixes = config.outputMixes.map { output in
                var updated = output
                updated.mix.inputs.removeAll { $0.source == source }
                return updated
            }.filter { !$0.mix.inputs.isEmpty }
            config.buses = config.buses.map { bus in
                var updated = bus
                updated.mix.inputs.removeAll { $0.source == source }
                return updated
            }
            config.mutedSources.removeAll { $0 == source }
            config.sourceLevels.removeAll { $0.source == source }
        }
    }

    private func setDeviceHidden(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "uid", "hidden"],
              let uid = body["uid"] as? String, !uid.isEmpty,
              let hidden = body["hidden"] as? Bool
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            let deviceUID = DeviceUID(rawValue: uid)
            config.hiddenDeviceUIDs.removeAll { $0 == deviceUID }
            if hidden {
                config.hiddenDeviceUIDs.append(deviceUID)
            }
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

    private func setDeviceMuted(body: [String: Any], requestID: String) throws {
        guard Set(body.keys) == ["requestId", "command", "uid", "muted"],
              let uid = body["uid"] as? String, !uid.isEmpty,
              let muted = body["muted"] as? Bool,
              let deviceCatalog else { throw BridgeError.invalidPayload }
        deviceCatalog.setOutputMuted(uid: uid, muted: muted) { [weak self] result in
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

    private func resetMix(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "target", "id"],
              let target = body["target"] as? String, ["output", "bus"].contains(target),
              let id = body["id"] as? String, !id.isEmpty
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            switch target {
            case "output":
                guard config.outputMixes.contains(where: { $0.deviceUID.rawValue == id }) else { throw BridgeError.unknownOutput }
                config.outputMixes.removeAll { $0.deviceUID.rawValue == id }
            case "bus":
                guard let uuid = UUID(uuidString: id),
                      let index = config.buses.firstIndex(where: { $0.id == uuid })
                else { throw BridgeError.unknownBus }
                config.buses[index].mix = Mix()
            default:
                throw BridgeError.invalidPayload
            }
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
        case "application", "app": source = .application(ApplicationID(rawValue: sourceID))
        case "bus":
            guard let id = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            source = .bus(id)
        default: throw BridgeError.invalidPayload
        }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            if case let .bus(id) = source {
                guard config.buses.contains(where: { $0.id == id }) else { throw BridgeError.unknownBus }
                config.mutedBuses.removeAll { $0 == id }
                if muted {
                    config.mutedBuses.append(id)
                }
                return
            }
            config.mutedSources.removeAll { $0 == source }
            if muted {
                config.mutedSources.append(source)
            }
        }
    }

    private func setSourceLevel(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "kind", "sourceID", "level"],
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty,
              let level = body["level"] as? Double, level.isFinite
        else {
            throw BridgeError.invalidPayload
        }
        let source: SourceReference
        switch kind {
        case "inputDevice": source = .inputDevice(DeviceUID(rawValue: sourceID))
        case "application", "app": source = .application(ApplicationID(rawValue: sourceID))
        default: throw BridgeError.invalidPayload
        }
        let maximum = if case .application = source {
            MixInput.maximumApplicationGain
        } else {
            1.0
        }
        guard (0 ... maximum).contains(level) else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            config.sourceLevels.removeAll { $0.source == source }
            if level != 1 {
                config.sourceLevels.append(SourceLevel(source: source, level: level))
            }
        }
    }

    private func setBusMuted(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id", "muted"],
              let idText = body["id"] as? String, let id = UUID(uuidString: idText),
              let muted = body["muted"] as? Bool else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            guard config.buses.contains(where: { $0.id == id }) else { throw BridgeError.unknownBus }
            config.mutedBuses.removeAll { $0 == id }
            if muted {
                config.mutedBuses.append(id)
            }
        }
    }

    private func createBus(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command"] else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            let existingNames = Set(candidate.buses.map(\.name))
            var index = 1
            while existingNames.contains("Virtual Bus \(index)") {
                index += 1
            }
            candidate.buses.append(VirtualBus(name: "Virtual Bus \(index)"))
        }
    }

    private func setBusChannelCount(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "id", "channelCount"],
              let idText = body["id"] as? String, let id = UUID(uuidString: idText),
              let count = body["channelCount"] as? Int,
              (1 ... VirtualBus.maximumChannelCount).contains(count)
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard let busIndex = candidate.buses.firstIndex(where: { $0.id == id }) else { throw BridgeError.unknownBus }
            let oldCount = candidate.buses[busIndex].channelCount
            guard oldCount != count else { return }
            var buses = candidate.buses
            var outputMixes = candidate.outputMixes
            buses[busIndex].channelCount = count
            func resizeSource(_ source: SourceReference, in mix: inout Mix) {
                guard let index = mix.inputs.firstIndex(where: { $0.source == source }) else { return }
                var row = mix.inputs[index]
                if count > oldCount {
                    row.channelRouting += Array(repeating: [], count: count - oldCount)
                    row.channelLevels += Array(repeating: 1, count: count - oldCount)
                } else {
                    row.channelRouting = Array(row.channelRouting.prefix(count))
                    row.channelLevels = Array(row.channelLevels.prefix(count))
                }
                mix.inputs[index] = row
            }
            for index in buses.indices where index != busIndex {
                resizeSource(.bus(id), in: &buses[index].mix)
            }
            for index in outputMixes.indices {
                resizeSource(.bus(id), in: &outputMixes[index].mix)
            }
            candidate.buses = buses
            candidate.outputMixes = outputMixes
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
            candidate.mutedBuses.removeAll { $0 == id }
            candidate.sourceLevels.removeAll { $0.source == .bus(id) }
        }
    }

    private func setVirtualMixLevel(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        guard Set(body.keys) == ["requestId", "command", "target", "id", "level"],
              let target = body["target"] as? String, target == "bus",
              let idString = body["id"] as? String, let id = UUID(uuidString: idString),
              let level = body["level"] as? Double, level.isFinite, (0 ... 1).contains(level)
        else { throw BridgeError.invalidPayload }
        return try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
            guard let index = candidate.buses.firstIndex(where: { $0.id == id }) else { throw BridgeError.unknownBus }
            candidate.buses[index].mix.level = level
            candidate.sourceLevels.removeAll { $0.source == .bus(id) }
        }
    }

    private enum MixInputOperation: Equatable { case add, remove, level, muted }

    // Keep payload validation and the atomic configuration update in one operation.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func editMixInput(body: [String: Any], store: ConfigurationStore, operation: MixInputOperation) throws -> MixerConfiguration {
        let common: Set = ["requestId", "command", "target", "id", "kind", "sourceID"]
        let expected = common.union(operation == .level ? ["level"] : (operation == .muted ? ["muted"] : []))
        guard Set(body.keys) == expected,
              let target = body["target"] as? String, ["output", "bus"].contains(target),
              let id = body["id"] as? String, !id.isEmpty,
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty
        else { throw BridgeError.invalidPayload }
        let reference: SourceReference
        switch kind {
        case "inputDevice": reference = .inputDevice(DeviceUID(rawValue: sourceID))
        case "application", "app": reference = .application(ApplicationID(rawValue: sourceID))
        case "bus":
            guard let busID = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            reference = .bus(busID)
        default: throw BridgeError.invalidPayload
        }
        let level = body["level"] as? Double
        if operation == .level {
            let maximum = 1.0
            guard let level, level.isFinite, (0 ... maximum).contains(level) else {
                throw BridgeError.invalidPayload
            }
        }
        let outputChannels: Int
        switch target {
        case "output":
            outputChannels = audioDevices.first(where: { $0.uid == id })?.outputChannels ?? 2
        case "bus":
            outputChannels = UUID(uuidString: id).flatMap { busID in
                configurationStore?.configuration.buses.first(where: { $0.id == busID })?.channelCount
            } ?? 2
        default:
            throw BridgeError.invalidPayload
        }
        let muted = body["muted"] as? Bool
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
                try applyInput(
                    operation, reference: reference, level: level, muted: muted,
                    outputChannels: outputChannels, to: &value
                )
                config.outputMixes[index].mix = value
                if operation == .remove, value.inputs.isEmpty {
                    config.outputMixes.remove(at: index)
                }
            case "bus":
                guard let uuid = UUID(uuidString: id),
                      let index = config.buses.firstIndex(where: { $0.id == uuid })
                else { throw BridgeError.unknownBus }
                var value = config.buses[index].mix
                try applyInput(
                    operation, reference: reference, level: level, muted: muted,
                    outputChannels: outputChannels, to: &value
                )
                config.buses[index].mix = value
            default:
                throw BridgeError.invalidPayload
            }
        }
    }

    // Each argument is a separately validated input to the mix edit.
    // swiftlint:disable:next function_parameter_count
    private func applyInput(
        _ operation: MixInputOperation,
        reference: SourceReference,
        level: Double?,
        muted: Bool?,
        outputChannels: Int,
        to mix: inout Mix
    ) throws {
        switch operation {
        case .add:
            guard !mix.inputs.contains(where: { $0.source == reference }) else { throw BridgeError.invalidPayload }
            if case let .inputDevice(uid) = reference {
                let channels = max(audioDevices.first(where: { $0.uid == uid.rawValue })?.inputChannels ?? 1, 1)
                let defaults = MixInput.physicalInputDefaults(channelCount: channels, outputChannels: outputChannels)
                mix.inputs.append(MixInput(source: reference, channelRouting: defaults.routing, channelLevels: defaults.levels))
            } else {
                let sourceChannels: Int = if case let .bus(id) = reference {
                    configurationStore?.configuration.buses.first(where: { $0.id == id })?.channelCount ?? 2
                } else {
                    2
                }
                let routing = MixInput.defaultRouting(channelCount: sourceChannels, outputChannels: outputChannels)
                mix.inputs.append(MixInput(
                    source: reference,
                    channelRouting: routing,
                    channelLevels: Array(repeating: 1, count: sourceChannels)
                ))
            }
        case .remove:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }) else {
                throw BridgeError.invalidPayload
            }
            mix.inputs.remove(at: index)
        case .level:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }), let level else { throw BridgeError.invalidPayload }
            mix.inputs[index].level = level
        case .muted:
            guard let index = mix.inputs.firstIndex(where: { $0.source == reference }), let muted else { throw BridgeError.invalidPayload }
            mix.inputs[index].isMuted = muted
        }
    }

    // Parsing and validating a channel matrix must precede the atomic update.
    // swiftlint:disable:next cyclomatic_complexity
    private func setMixInputRouting(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        let expected: Set = ["requestId", "command", "target", "id", "kind", "sourceID", "channelRouting"]
        guard Set(body.keys) == expected,
              let target = body["target"] as? String,
              let destinationID = body["id"] as? String,
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String,
              let raw = body["channelRouting"] as? [[Int]],
              (1 ... 64).contains(raw.count),
              raw.allSatisfy({ row in
                  Set(row).count == row.count && row.allSatisfy { $0 > 0 }
              })
        else { throw BridgeError.invalidPayload }
        let currentConfiguration = store.configuration
        let destinationChannels: Int
        switch target {
        case "output":
            destinationChannels = audioDevices.first(where: { $0.uid == destinationID })?.outputChannels ?? Int.max
        case "bus":
            destinationChannels = UUID(uuidString: destinationID).flatMap { busID in
                currentConfiguration.buses.first(where: { $0.id == busID })?.channelCount
            } ?? 0
        default:
            throw BridgeError.invalidPayload
        }
        guard raw.allSatisfy({ $0.allSatisfy { $0 <= destinationChannels } }) else { throw BridgeError.invalidPayload }
        return try updateMixChannels(body: body, store: store) { input in
            let expectedChannels: Int
            switch input.source {
            case let .inputDevice(uid):
                guard kind == "inputDevice", uid.rawValue == sourceID else { throw BridgeError.invalidPayload }
                let discoveredChannels = audioDevices.first(where: { $0.uid == uid.rawValue })?.inputChannels ?? 0
                expectedChannels = max(input.channelRouting.count, discoveredChannels)
            case let .application(id):
                guard kind == "app" || kind == "application" else { throw BridgeError.invalidPayload }
                expectedChannels = 2
                guard id.rawValue == sourceID else { throw BridgeError.invalidPayload }
            case let .bus(busID):
                guard kind == "bus", busID.uuidString == sourceID else { throw BridgeError.invalidPayload }
                expectedChannels = currentConfiguration.buses.first(where: { $0.id == busID })?.channelCount ?? 0
            }
            guard expectedChannels > 0, raw.count == expectedChannels else { throw BridgeError.invalidPayload }
            input.channelRouting = raw
            if input.channelLevels.count < raw.count {
                input.channelLevels += Array(repeating: 1, count: raw.count - input.channelLevels.count)
            }
        }
    }

    private func setMixInputChannels(body: [String: Any], store: ConfigurationStore) throws -> MixerConfiguration {
        let expected: Set = ["requestId", "command", "target", "id", "kind", "sourceID", "channelLevels"]
        guard Set(body.keys) == expected,
              let kind = body["kind"] as? String,
              ["inputDevice", "app", "bus"].contains(kind),
              let levels = body["channelLevels"] as? [Double],
              levels.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) })
        else { throw BridgeError.invalidPayload }
        return try updateMixChannels(body: body, store: store) { input in
            let expectedChannels: Int
            switch input.source {
            case let .inputDevice(uid):
                guard kind == "inputDevice" else { throw BridgeError.invalidPayload }
                expectedChannels = max(input.channelLevels.count, audioDevices.first(where: { $0.uid == uid.rawValue })?.inputChannels ?? 0)
            case .application:
                guard kind == "app" else { throw BridgeError.invalidPayload }
                expectedChannels = 2
            case .bus:
                guard kind == "bus",
                      let sourceID = body["sourceID"] as? String,
                      let busID = UUID(uuidString: sourceID),
                      case let .bus(inputBusID) = input.source,
                      busID == inputBusID
                else { throw BridgeError.invalidPayload }
                expectedChannels = store.configuration.buses.first(where: { $0.id == busID })?.channelCount ?? 0
            }
            guard expectedChannels > 0, levels.count == expectedChannels else { throw BridgeError.invalidPayload }
            if input.channelRouting.count < levels.count {
                input.channelRouting += Array(repeating: [], count: levels.count - input.channelRouting.count)
            }
            input.channelLevels = levels
        }
    }

    // Resolve the target and source together before accepting the edit.
    // swiftlint:disable:next cyclomatic_complexity
    private func updateMixChannels(
        body: [String: Any], store: ConfigurationStore, edit: (inout MixInput) throws -> Void
    ) throws -> MixerConfiguration {
        guard let target = body["target"] as? String, ["output", "bus"].contains(target),
              let id = body["id"] as? String, !id.isEmpty,
              let kind = body["kind"] as? String,
              let sourceID = body["sourceID"] as? String, !sourceID.isEmpty
        else { throw BridgeError.invalidPayload }
        let reference: SourceReference
        switch kind {
        case "inputDevice": reference = .inputDevice(DeviceUID(rawValue: sourceID))
        case "app": reference = .application(ApplicationID(rawValue: sourceID))
        case "bus":
            guard let uuid = UUID(uuidString: sourceID) else { throw BridgeError.invalidPayload }
            reference = .bus(uuid)
        default: throw BridgeError.invalidPayload
        }
        return try store.update(discoveredDevices: discoveredDescriptors()) { config in
            func update(_ mix: inout Mix) throws {
                guard let index = mix.inputs.firstIndex(where: { $0.source == reference }) else { throw BridgeError.invalidPayload }
                try edit(&mix.inputs[index])
            }
            switch target {
            case "output":
                guard let index = config.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == id })
                else { throw BridgeError.unknownOutput }
                try update(&config.outputMixes[index].mix)
            case "bus":
                guard let uuid = UUID(uuidString: id),
                      let index = config.buses.firstIndex(where: { $0.id == uuid })
                else { throw BridgeError.unknownBus }
                try update(&config.buses[index].mix)
            default:
                throw BridgeError.invalidPayload
            }
        }
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
                outputChannels: $0.outputChannels, sampleRate: $0.nominalSampleRate
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
            let deviceLevels = coordinator.deviceLevelReadings()
            DispatchQueue.main.async {
                guard let self else { return }
                self.sourceLevels = sourceLevels
                self.inputChannelLevels = inputChannelLevels
                self.renderLevels = renderLevels
                self.deviceLevels = deviceLevels
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
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            isEnabled: configuration.isEnabled,
            devices: bridgeDevices(configuration: configuration, discovered: discovered),
            outputs: bridgeOutputs(configuration: configuration, discovered: discovered, deviceLevels: deviceLevels),
            buses: configuration.buses.map { bus in
                BridgeNamedItem(
                    id: bus.id.uuidString, name: bus.name, category: "virtual",
                    muted: configuration.mutedBuses.contains(bus.id), sourceLevel: bus.mix.level,
                    channelCount: bus.channelCount
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
                case let .application(app): kind = "app"; sourceID = app.rawValue
                case let .bus(bus): kind = "bus"; sourceID = bus.uuidString
                }
                let channelMeters: [Double?] = if case let .bus(busID) = input.source,
                                                  let bus = configuration.buses.first(where: { $0.id == busID })
                {
                    (1 ... bus.channelCount).map { renderLevels["bus:\(busID.uuidString)/channel/\($0)"] }
                } else {
                    []
                }
                return BridgeMixInput(
                    kind: kind,
                    id: sourceID,
                    level: input.level,
                    channelRouting: input.channelRouting,
                    channelLevels: input.channelLevels,
                    channelMeters: channelMeters,
                    muted: input.isMuted,
                    sourceMuted: configuration.mutedSources.contains(input.source),
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
        func hasSettings(_ mix: Mix) -> Bool {
            !mix.inputs.isEmpty || mix.level != 1
        }
        return configuration.outputMixes.filter { hasSettings($0.mix) }.map { item("output", $0.deviceUID.rawValue, $0.mix) }
            + configuration.buses.filter { hasSettings($0.mix) }.map { item("bus", $0.id.uuidString, $0.mix) }
    }

    func bridgeApplications(configuration: MixerConfiguration, sourceLevels: [String: Double]) -> [BridgeApplication] {
        let configuredIDs = configuration.applications.map(\.rawValue) + (configuration.outputMixes.map(\.mix)
            + configuration.buses.map(\.mix))
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
                captureState: captureStates["application:\(id)"] ?? "stopped",
                muted: configuration.mutedSources.contains(.application(ApplicationID(rawValue: id))),
                level: sourceLevels["application:\(id)"],
                registered: configuration.applications.contains(ApplicationID(rawValue: id)),
                sourceLevel: configuration.sourceLevels.first(where: {
                    $0.source == .application(ApplicationID(rawValue: id))
                })?.level ?? 1,
                channelLevels: inputChannelLevels["application:\(id)"] ?? []
            )
        }
    }

    func bridgeDevices(configuration: MixerConfiguration, discovered: [String: AudioDeviceSnapshot]) -> [BridgeDevice] {
        let savedUIDs = configuration.knownDevices.map(\.uid.rawValue)
        let hiddenUIDs = configuration.hiddenDeviceUIDs.map(\.rawValue)
        let deviceUIDs = Set(discovered.keys).union(savedUIDs).union(hiddenUIDs).sorted()
        return deviceUIDs.map { uid -> BridgeDevice in
            let live = discovered[uid]
            let deviceUID = DeviceUID(rawValue: uid)
            var savedAs: [String] = []
            if configuration.outputMixes.contains(where: { $0.deviceUID == deviceUID && !$0.mix.inputs.isEmpty }) {
                savedAs.append("output")
            }
            let mixes = configuration.outputMixes.map(\.mix) + configuration.buses.map(\.mix)
            let isSavedInput = mixes.flatMap(\.inputs).contains { input in
                if case let .inputDevice(inputUID) = input.source {
                    return inputUID == deviceUID
                }
                return false
            }
            if isSavedInput {
                savedAs.append("input")
            }
            let name = live?.name ?? configuration.deviceDisplayName(for: deviceUID)
            return BridgeDevice(
                uid: uid,
                name: name,
                category: "system",
                discovered: live != nil,
                available: live.map { $0.isAlive && !configuration.hiddenDeviceUIDs.contains(deviceUID) } ?? false,
                inputChannels: live?.inputChannels ?? 0,
                outputChannels: live?.outputChannels ?? 0,
                savedAs: savedAs,
                muted: configuration.mutedSources.contains(.inputDevice(deviceUID)),
                sourceLevel: configuration.sourceLevels.first(where: { $0.source == .inputDevice(deviceUID) })?.level ?? 1,
                hidden: configuration.hiddenDeviceUIDs.contains(deviceUID)
            )
        }
    }

    func bridgeOutputs(
        configuration: MixerConfiguration,
        discovered: [String: AudioDeviceSnapshot],
        deviceLevels: [String: Double] = [:]
    ) -> [BridgeOutput] {
        let saved = Dictionary(uniqueKeysWithValues: configuration.outputMixes.map { ($0.deviceUID.rawValue, $0) })
        let discoveredOutputUIDs = audioDevices.filter { $0.outputChannels > 0 }.map(\.uid)
        return Set(discoveredOutputUIDs).union(saved.keys).sorted().map { uid -> BridgeOutput in
            let live = discovered[uid]
            let name = live?.name ?? configuration.deviceDisplayName(for: DeviceUID(rawValue: uid))
            return BridgeOutput(
                uid: uid,
                name: name,
                category: "system",
                available: live.map {
                    $0.isAlive && $0.outputChannels > 0 &&
                        !configuration.hiddenDeviceUIDs.contains(DeviceUID(rawValue: uid))
                } ?? false,
                outputChannels: live?.outputChannels ?? 0,
                volume: live?.outputVolume,
                volumeWritable: live?.canSetOutputVolume ?? false,
                muted: live?.outputMuted,
                muteWritable: live?.canSetOutputMute ?? false,
                configured: saved[uid] != nil,
                routeError: outputRouteErrors[uid],
                levelReading: configuration.hiddenDeviceUIDs.contains(DeviceUID(rawValue: uid)) ? nil :
                    (live?.outputMuted == true || live?.outputVolume == 0 ? 0 : deviceLevels[uid]),
                meterState: captureStates["device:\(uid)"]
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
