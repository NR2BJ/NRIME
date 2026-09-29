import AppKit

/// Settings behaves as an ordinary app while it is open: it shows in the Dock
/// and the app switcher, so its window cannot get lost behind others (as it
/// could when it ran as a background-only app), and it quits when its window
/// closes, taking the Dock icon with it.
///
/// An update that is downloading or installing keeps it running; the Dock
/// icon then stays until that finishes or the user quits.
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if SettingsSnapshots.renderIfRequested() { return }
#endif
        // Opened from the input method's menu while another app is in front.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UpdateManager.shared.isBusy
    }
}
