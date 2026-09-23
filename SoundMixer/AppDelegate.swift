import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?

    func applicationDidFinishLaunching(_: Notification) {
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
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        self.window = window
        self.webView = webView

        guard let webDirectory = Bundle.main.url(forResource: "dist", withExtension: nil),
              let indexURL = URL(string: "index.html", relativeTo: webDirectory)
        else {
            showLoadError("Локальный интерфейс не найден в приложении.")
            window.makeKeyAndOrderFront(nil)
            return
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        showLoadError("Не удалось открыть локальный интерфейс: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        showLoadError("Не удалось загрузить локальный интерфейс: \(error.localizedDescription)")
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
