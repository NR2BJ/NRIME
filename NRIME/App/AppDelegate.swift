import Cocoa
import InputMethodKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var server: IMKServer!
    var candidatePanel: CandidatePanel!

    private var statusItem: NSStatusItem!
    private var modeItems: [(mode: InputMode, item: NSMenuItem)] = []
    private var settingsItem: NSMenuItem?
    private var restartItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    /// The settings app's language, read when the menu opens (not on every
    /// mode switch, which only needs it for the tooltip).
    private var menuLanguage = AppDelegate.settingsAppLanguage()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String
            ?? Bundle.main.bundleIdentifier! + "_Connection"

        server = IMKServer(
            name: connectionName,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        candidatePanel = CandidatePanel()
        // Load Mozc now (7–20 ms) so the first conversion does not pay for it,
        // and look for a newer one from time to time. Tests load it
        // themselves, with a throwaway profile, when they need it.
        if !AppGroupDefaults.isRunningTests {
            MozcEngine.shared.start()
            MozcUpdater.shared.start()
        }

        InputSourceRecovery.shared.startMonitoring()
        DeveloperLogger.shared.startMainThreadStallMonitor()
        PermissionMonitor.start()
        setupStatusItem()

        NSLog("NRIME: Server started with connection name: \(connectionName)")
        DeveloperLogger.shared.log("App", "Server started", metadata: [
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "connection": connectionName
        ])
    }

    /// Updates and logout quit the input method with Mozc sessions still open;
    /// save what it learned first.
    func applicationWillTerminate(_ notification: Notification) {
        if !AppGroupDefaults.isRunningTests {
            MozcEngine.shared.sync()
        }
    }

    // MARK: - Menu Bar Status Item

    /// The current mode's letter in the menu bar. Its menu picks the mode (the
    /// current one checked) — choosing one while another input source is
    /// selected selects NRIME too — above settings, restart and quit.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatusIcon(for: StateManager.shared.currentMode)

        // Listen for mode changes
        StateManager.shared.onStatusIconUpdate = { [weak self] mode in
            self?.updateStatusIcon(for: mode)
        }

        let menu = NSMenu()
        menu.delegate = self

        for mode in [InputMode.english, .korean, .japanese] {
            let item = NSMenuItem(title: "", action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.image = makeStatusIcon(text: mode.label, side: 16, fontSize: 12)
            menu.addItem(item)
            modeItems.append((mode, item))
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        self.settingsItem = settingsItem

        let restartItem = NSMenuItem(title: "", action: #selector(restartApp), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)
        self.restartItem = restartItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        self.quitItem = quitItem

        statusItem.menu = menu
        titleMenuItems()
    }

    /// Each time the menu opens: titles in the settings app's language (it
    /// may have changed) and the current mode checked.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menuLanguage = Self.settingsAppLanguage()
        titleMenuItems()
        let current = StateManager.shared.currentMode
        for (mode, item) in modeItems {
            item.state = mode == current ? .on : .off
        }
        statusItem?.button?.toolTip = statusToolTip(for: current)
    }

    private func titleMenuItems() {
        let language = menuLanguage
        for (mode, item) in modeItems {
            item.title = Self.modeName(mode, in: language)
        }
        settingsItem?.title = Self.text("NRIME 설정…", "NRIME Settings…", "NRIME 設定…", in: language)
        restartItem?.title = Self.text("NRIME 다시 시작", "Restart NRIME", "NRIME を再起動", in: language)
        quitItem?.title = Self.text("NRIME 종료", "Quit NRIME", "NRIME を終了", in: language)
    }

    /// The language picked in the settings app's About tab: "ko" (its
    /// default), "en" or "ja".
    private static func settingsAppLanguage() -> String {
        let domain = "com.nrime.settings" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("appLanguage" as CFString, domain) as? String ?? "ko"
    }

    private static func text(_ ko: String, _ en: String, _ ja: String, in language: String) -> String {
        switch language {
        case "en": return en
        case "ja": return ja
        default: return ko
        }
    }

    private static func modeName(_ mode: InputMode, in language: String) -> String {
        switch mode {
        case .english: return text("영어", "English", "英語", in: language)
        case .korean: return text("한국어", "Korean", "韓国語", in: language)
        case .japanese: return text("일본어", "Japanese", "日本語", in: language)
        }
    }

    func updateStatusIcon(for mode: InputMode) {
        guard let button = statusItem?.button else { return }
        button.image = makeStatusIcon(text: mode.label)
        button.title = ""
        button.toolTip = statusToolTip(for: mode)
    }

    private func statusToolTip(for mode: InputMode) -> String {
        "NRIME: " + Self.modeName(mode, in: menuLanguage)
    }

    /// A mode picked from the menu (NRIMEInputController.chooseModeFromMenu).
    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = InputMode(rawValue: raw) else { return }
        NRIMEInputController.chooseModeFromMenu(mode)
    }

    /// Render a mode letter as a template image, for the menu bar (and a little
    /// smaller for the menu items) — handles Retina/non-HiDPI automatically.
    private func makeStatusIcon(text: String, side: CGFloat = 18, fontSize: CGFloat = 14) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
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
        // Mozc runs inside the input method (since 1.0.12-beta.2) and saves on
        // termination; there is no mozc_server to stop any more.

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
