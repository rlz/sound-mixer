import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var configurationStore: ConfigurationStore?
    private var deviceCatalog: CoreAudioDeviceCatalog?
    private var audioDevices: [AudioDeviceSnapshot] = []

    func applicationDidFinishLaunching(_: Notification) {
        var configurationError: Error?
        do {
            let identifier = Bundle.main.bundleIdentifier ?? "com.rlz.soundmixer"
            configurationStore = try ConfigurationStore(fileURL: ConfigurationStore.defaultFileURL(bundleIdentifier: identifier))
        } catch {
            configurationError = error
        }

        let deviceCatalog = CoreAudioDeviceCatalog()
        deviceCatalog.onChange = { [weak self] devices in
            self?.audioDevices = devices
            self?.publishState()
        }
        self.deviceCatalog = deviceCatalog
        deviceCatalog.start()

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
        self.window = window
        self.webView = webView

        guard let webDirectory = Bundle.main.url(forResource: "dist", withExtension: nil),
              let indexURL = URL(string: "index.html", relativeTo: webDirectory)
        else {
            showLoadError("The local interface was not found in the app bundle.")
            window.makeKeyAndOrderFront(nil)
            return
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)
        if configurationError != nil {
            showLoadError(
                "The saved configuration could not be loaded. Mixing is off and the file was preserved. " +
                    "Check or repair the configuration before editing."
            )
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
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
                guard Set(body.keys) == ["requestId", "command"] else { throw BridgeError.invalidPayload }
                sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
                publishState()
                return
            }
            guard let store = configurationStore else { throw BridgeError.storageUnavailable }
            let configuration: MixerConfiguration
            switch command {
            case "setMasterEnabled":
                guard Set(body.keys) == ["requestId", "command", "enabled"],
                      let enabled = body["enabled"] as? Bool
                else { throw BridgeError.invalidPayload }
                configuration = try store.update(discoveredDevices: discoveredDescriptors()) {
                    $0.isEnabled = enabled
                }
            case "setOutputLevel":
                guard Set(body.keys) == ["requestId", "command", "uid", "level"],
                      let uid = body["uid"] as? String, !uid.isEmpty,
                      let level = body["level"] as? Double, (0 ... 1).contains(level)
                else { throw BridgeError.invalidPayload }
                configuration = try store.update(discoveredDevices: discoveredDescriptors()) { candidate in
                    guard let index = candidate.outputMixes.firstIndex(where: { $0.deviceUID.rawValue == uid }) else {
                        throw BridgeError.unknownOutput
                    }
                    candidate.outputMixes[index].mix.level = level
                }
            default:
                throw BridgeError.unknownCommand
            }
            sendToWeb(method: "onCommandResult", payload: ["requestId": requestID, "accepted": true])
            publishState(configuration: configuration)
        } catch {
            sendToWeb(method: "onCommandResult", payload: [
                "requestId": requestID,
                "accepted": false,
                "error": error.localizedDescription,
            ])
        }
    }

    private func discoveredDescriptors() -> [AudioDeviceDescriptor] {
        audioDevices.map {
            AudioDeviceDescriptor(
                uid: DeviceUID(rawValue: $0.uid), name: $0.name, inputChannels: $0.inputChannels,
                outputChannels: $0.outputChannels, sampleRate: $0.nominalSampleRate,
                isBlackHole: $0.name.localizedCaseInsensitiveContains("BlackHole")
            )
        }
    }

    private func publishState(configuration: MixerConfiguration? = nil) {
        guard let configuration = configuration ?? configurationStore?.configuration else { return }
        let discovered = Dictionary(uniqueKeysWithValues: audioDevices.map { ($0.uid, $0) })
        let saved = Dictionary(uniqueKeysWithValues: configuration.outputMixes.map { ($0.deviceUID.rawValue, $0) })
        let discoveredOutputUIDs = audioDevices.filter { $0.outputChannels > 0 }.map(\.uid)
        let devices = Set(discoveredOutputUIDs).union(saved.keys).sorted().map { uid -> BridgeOutput in
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
        let state = BridgeState(
            schemaVersion: MixerConfiguration.currentSchemaVersion,
            isEnabled: configuration.isEnabled,
            outputs: devices,
            buses: configuration.buses.map { BridgeNamedItem(id: $0.id.uuidString, name: $0.name) },
            blackHoleRoutes: configuration.blackHoleRoutes.map { BridgeNamedItem(id: $0.id.uuidString, name: $0.name) }
        )
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView?.evaluateJavaScript("window.soundMixerBridge?.onState(\(json))")
    }

    private func sendToWeb(method: String, payload: [String: Any]) {
        guard let webView, JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        webView.evaluateJavaScript("window.soundMixerBridge?.\(method)(\(json))")
    }

    private func showLoadError(_ message: String) {
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
    let outputs: [BridgeOutput]
    let buses: [BridgeNamedItem]
    let blackHoleRoutes: [BridgeNamedItem]
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
