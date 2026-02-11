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

        InputSourceRecovery.shared.startMonitoring()
        setupStatusItem()

        NSLog("NRIME: Server started with connection name: \(connectionName)")
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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NRIME", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateStatusIcon(for mode: InputMode) {
        guard let button = statusItem?.button else { return }

        if let icon = NSImage(named: mode.iconName) {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.title = ""
        } else {
            // Fallback: use text label
            button.image = nil
            button.title = mode.label
        }
    }

    @objc private func openSettings() {
        let bundlePath = Bundle.main.bundlePath
        let appDir = (bundlePath as NSString).deletingLastPathComponent
        let companionPath = (appDir as NSString).appendingPathComponent("NRIMESettings.app")

        if FileManager.default.fileExists(atPath: companionPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: companionPath))
        } else {
            NSLog("NRIME: Companion app not found at \(companionPath)")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
