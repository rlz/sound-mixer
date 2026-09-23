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
                self?.captureStates[route] = "unavailable: \(error)"
                self?.publishState()
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
        case "setMasterEnabled":
            guard Set(body.keys) == ["requestId", "command", "enabled"],
                  let enabled = body["enabled"] as? Bool
            else { throw BridgeError.invalidPayload }
            return try store.update(discoveredDevices: discoveredDescriptors()) { $0.isEnabled = enabled }
        case "setOutputLevel":
            guard Set(body.keys) == ["requestId", "command", "uid", "level"],
                  let uid = body["uid"] as? String, !uid.isEmpty,
                  let level = body["level"] as? Double, (0 ... 1).contains(level)
            else { throw BridgeError.invalidPayload }
            return try updateOutputLevel(store: store, uid: uid, level: level)
        default:
            throw BridgeError.unknownCommand
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
        audioRoutingCoordinator?.update(graph: graph, devices: audioDevices, processes: audioProcesses)
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
            blackHoleRoutes: configuration.blackHoleRoutes.map { BridgeNamedItem(id: $0.id.uuidString, name: $0.name) },
            applications: audioProcesses.map {
                BridgeApplication(
                    id: $0.applicationID,
                    name: $0.name,
                    available: $0.isProducingOutput,
                    captureState: captureStates[$0.applicationID] ?? "stopped"
                )
            },
            inputCaptureStates: captureStates.filter { id, _ in audioDevices.contains(where: { $0.uid == id }) }
                .map { BridgeInputCaptureState(uid: $0.key, state: $0.value) }
        )
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.soundMixerBridge?.onState(\(json))")
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
                available: live.map { $0.isAlive && $0.outputChannels > 0 } ?? false,
                outputChannels: live?.outputChannels ?? 0,
                level: saved[uid]?.mix.level ?? 1,
                configured: saved[uid] != nil
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

private struct BridgeState: Encodable {
    let schemaVersion: Int
    let isEnabled: Bool
    let devices: [BridgeDevice]
    let outputs: [BridgeOutput]
    let buses: [BridgeNamedItem]
    let blackHoleRoutes: [BridgeNamedItem]
    let applications: [BridgeApplication]
    let inputCaptureStates: [BridgeInputCaptureState]
}

private struct BridgeApplication: Encodable {
    let id: String
    let name: String
    let available: Bool
    let captureState: String
}

private struct BridgeInputCaptureState: Encodable {
    let uid: String
    let state: String
}

private struct BridgeDevice: Encodable {
    let uid: String
    let name: String
    let discovered: Bool
    let available: Bool
    let inputChannels: Int
    let outputChannels: Int
    let savedAs: [String]
}

private struct BridgeOutput: Encodable {
    let uid: String
    let name: String
    let available: Bool
    let outputChannels: Int
    let level: Double
    let configured: Bool
}

private struct BridgeNamedItem: Encodable {
    let id: String
    let name: String
}

private enum BridgeError: LocalizedError {
    case storageUnavailable
    case invalidPayload
    case unknownCommand
    case unknownOutput

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Configuration storage is unavailable."
        case .invalidPayload: "The command contains invalid values."
        case .unknownCommand: "The command is not supported."
        case .unknownOutput: "The output is not present in the saved configuration."
        }
    }
}
