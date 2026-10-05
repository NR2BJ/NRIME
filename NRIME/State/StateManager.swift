import Cocoa

final class StateManager {
    static let shared = StateManager()

    /// Korean when the input method starts (login, update, restart) — the
    /// language the owner starts typing in. The last mode is not restored.
    static let initialMode: InputMode = .korean

    private(set) var currentMode: InputMode = StateManager.initialMode
    private var previousNonEnglishMode: InputMode
    private var currentAppBundleId: String?

    /// Callback for updating the menu bar status icon. Set by AppDelegate.
    /// The menu bar is the only place the mode is shown: the indicator next
    /// to the text cursor was removed on 2026-10-06, as no lookup finds the
    /// cursor in every app (Chromium answers with zero-size or stale rects).
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
        onStatusIconUpdate = nil
    }
#endif
}
