import Cocoa

final class StateManager {
    static let shared = StateManager()

    private(set) var currentMode: InputMode = .english
    private var previousNonEnglishMode: InputMode = .korean
    private var currentAppBundleId: String?

    /// Callback invoked when mode changes. Set by NRIMEInputController.
    var onModeChanged: ((InputMode) -> Void)?

    /// Callback for updating the menu bar status icon. Set by AppDelegate.
    var onStatusIconUpdate: ((InputMode) -> Void)?

    private init() {}

    /// Toggle between English and the previous non-English mode.
    func toggleEnglish() {
        if currentMode == .english {
            switchTo(previousNonEnglishMode)
        } else {
            switchTo(.english)
        }
    }

    /// Switch directly to a specific mode.
    func switchTo(_ mode: InputMode) {
        guard mode != currentMode else { return }

        if currentMode != .english {
            previousNonEnglishMode = currentMode
        }

        currentMode = mode
        NSLog("NRIME: Mode changed to \(mode.label)")

        onModeChanged?(mode)
        onStatusIconUpdate?(mode)
    }

    // MARK: - Per-App Mode Memory

    /// Called when an app gains focus. Restores saved mode if applicable.
    func activateApp(_ bundleId: String) {
        currentAppBundleId = bundleId
        guard Settings.shared.perAppModeEnabled else { return }
        guard shouldRememberApp(bundleId) else { return }

        let saved = Settings.shared.perAppSavedModes
        if let rawValue = saved[bundleId],
           let mode = InputMode(rawValue: rawValue) {
            if mode != currentMode {
                currentMode = mode
                if currentMode != .english {
                    previousNonEnglishMode = currentMode
                }
                NSLog("NRIME: Restored mode \(mode.label) for app \(bundleId)")
                onModeChanged?(mode)
                onStatusIconUpdate?(mode)
            }
        }
    }

    /// Called when an app loses focus. Saves current mode if applicable.
    func deactivateApp(_ bundleId: String) {
        guard Settings.shared.perAppModeEnabled else { return }
        guard shouldRememberApp(bundleId) else { return }

        var saved = Settings.shared.perAppSavedModes
        saved[bundleId] = currentMode.rawValue
        Settings.shared.perAppSavedModes = saved
    }

    private func shouldRememberApp(_ bundleId: String) -> Bool {
        let list = Settings.shared.perAppModeList
        let isInList = list.contains(bundleId)

        switch Settings.shared.perAppModeType {
        case "whitelist":
            return isInList
        case "blacklist":
            return !isInList
        default:
            return false
        }
    }
}
