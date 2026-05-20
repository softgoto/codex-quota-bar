import AppKit
import CodexQuotaCore

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = CodexJSONLQuotaProvider()
        let store = QuotaStore(provider: provider)
        statusBarController = StatusBarController(store: store)
        store.startPolling()
    }
}
