import Cocoa

final class StateManager {
    static let shared = StateManager()

    private(set) var currentMode: InputMode = .english
    private var previousNonEnglishMode: InputMode
    private var currentAppBundleId: String?

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

    // MARK: - Active App

    /// Called when an app gains focus. Only recorded for the developer log:
    /// the mode is global and never restored per app.
    func activateApp(_ bundleId: String) {
        currentAppBundleId = bundleId
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
        onModeChanged = nil
        onStatusIconUpdate = nil
    }
#endif
}
