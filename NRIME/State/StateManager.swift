import Cocoa

final class StateManager {
    static let shared = StateManager()

    private(set) var currentMode: InputMode = .english
    private var previousNonEnglishMode: InputMode
    private var currentAppBundleId: String?
    private var hasCompletedInitialActivation = false

    /// Callback invoked when mode changes. Set by NRIMEInputController.
    var onModeChanged: ((InputMode) -> Void)?

    /// Callback for updating the menu bar status icon. Set by AppDelegate.
    var onStatusIconUpdate: ((InputMode) -> Void)?

    private init() {
        previousNonEnglishMode = Settings.shared.lastNonEnglishMode
    }

    /// Cycle between non-English modes (Korean ↔ Japanese).
    /// If currently English, switches to the opposite of previousNonEnglishMode.
    func toggleNonEnglish() {
        switch currentMode {
        case .korean:
            switchTo(.japanese)
        case .japanese:
            switchTo(.korean)
        case .english:
            let opposite: InputMode = previousNonEnglishMode == .korean ? .japanese : .korean
            switchTo(opposite)
        }
    }

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

        if mode == .english, currentMode != .english {
            rememberNonEnglishMode(currentMode)
        }

        currentMode = mode
        if mode != .english {
            rememberNonEnglishMode(mode)
        }
        NSLog("NRIME: Mode changed to \(mode.label)")
        DeveloperLogger.shared.log("StateManager", "Mode changed", metadata: [
            "app": currentAppBundleId ?? "unknown",
            "mode": mode.label,
            "sourceID": mode.rawValue
        ])

        onModeChanged?(mode)
        onStatusIconUpdate?(mode)
    }

    // MARK: - Per-App Mode Memory

    /// Called when an app gains focus. Restores saved mode if applicable.
    func activateApp(_ bundleId: String) {
        currentAppBundleId = bundleId
        defer { hasCompletedInitialActivation = true }
        guard Settings.shared.perAppModeEnabled else { return }
        guard shouldRememberApp(bundleId) else { return }

        let saved = Settings.shared.perAppSavedModes
        if let rawValue = saved[bundleId],
           let mode = InputMode(rawValue: rawValue) {
            if !hasCompletedInitialActivation && currentMode == .english && mode != .english {
                DeveloperLogger.shared.log("StateManager", "Skipped per-app restore on initial activation", metadata: [
                    "app": bundleId,
                    "mode": mode.label,
                    "sourceID": mode.rawValue
                ])
                return
            }
            if mode != currentMode {
                currentMode = mode
                if currentMode != .english {
                    rememberNonEnglishMode(currentMode)
                }
                NSLog("NRIME: Restored mode \(mode.label) for app \(bundleId)")
                DeveloperLogger.shared.log("StateManager", "Restored per-app mode", metadata: [
                    "app": bundleId,
                    "mode": mode.label,
                    "sourceID": mode.rawValue
                ])
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

    private func rememberNonEnglishMode(_ mode: InputMode) {
        guard mode != .english else { return }
        previousNonEnglishMode = mode
        Settings.shared.lastNonEnglishMode = mode
    }

    func reloadPersistedModePreferences() {
        previousNonEnglishMode = Settings.shared.lastNonEnglishMode
    }

#if DEBUG
    func resetForTesting() {
        currentMode = .english
        previousNonEnglishMode = Settings.shared.lastNonEnglishMode
        currentAppBundleId = nil
        hasCompletedInitialActivation = false
        onModeChanged = nil
        onStatusIconUpdate = nil
    }
#endif
}
