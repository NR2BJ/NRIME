import Cocoa
import InputMethodKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer!
    var candidatePanel: CandidatePanel!

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
            ?? Bundle.main.bundleIdentifier! + "_Connection"

        server = IMKServer(
            name: connectionName,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        candidatePanel = CandidatePanel()
        MozcServerManager.shared.prewarmServer()

        InputSourceRecovery.shared.startMonitoring()
        setupStatusItem()

        NSLog("NRIME: Server started with connection name: \(connectionName)")
        DeveloperLogger.shared.log("App", "Server started", metadata: [
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "connection": connectionName
        ])
    }

    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatusIcon(for: StateManager.shared.currentMode)

        // Listen for mode changes
        StateManager.shared.onStatusIconUpdate = { [weak self] mode in
            self?.updateStatusIcon(for: mode)
        }

        // Build menu
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "NRIME Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let restartItem = NSMenuItem(title: "Restart NRIME", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NRIME", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateStatusIcon(for mode: InputMode) {
        guard let button = statusItem?.button else { return }
        button.image = makeStatusIcon(text: mode.label)
        button.title = ""
    }

    /// Render menu bar icon at runtime — handles Retina/non-HiDPI automatically.
    private func makeStatusIcon(text: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 14, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            let textSize = str.size()
            str.draw(at: NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2
            ))
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func openSettings() {
        let bundlePath = Bundle.main.bundlePath
        let appDir = (bundlePath as NSString).deletingLastPathComponent
        let companionPath = (appDir as NSString).appendingPathComponent("NRIMESettings.app")

        guard FileManager.default.fileExists(atPath: companionPath) else {
            NSLog("NRIME: Companion app not found at \(companionPath)")
            return
        }

        // Use /usr/bin/open — most reliable way to launch and activate
        // from a background IMKit app.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", companionPath]
        try? task.run()
    }

    @objc private func restartApp() {
        DeveloperLogger.shared.log("App", "Restart requested")
        // Kill mozc_server
        let mozcTask = Process()
        mozcTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        mozcTask.arguments = ["mozc_server"]
        try? mozcTask.run()
        mozcTask.waitUntilExit()

        // Kill NRIMESettings if running
        let settingsTask = Process()
        settingsTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        settingsTask.arguments = ["NRIMESettings"]
        try? settingsTask.run()
        settingsTask.waitUntilExit()

        // Terminate self — macOS auto-restarts the IME
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        DeveloperLogger.shared.log("App", "Quit requested")
        NSApp.terminate(nil)
    }
}

// MARK: - Convenience Accessor

extension NSApplication {
    /// Shorthand for `(NSApp.delegate as? AppDelegate)?.candidatePanel`.
    var candidatePanel: CandidatePanel? {
        (delegate as? AppDelegate)?.candidatePanel
    }
}
