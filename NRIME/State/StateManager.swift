import Cocoa

final class StateManager {
    static let shared = StateManager()

    private(set) var currentMode: InputMode = .english
    private var previousNonEnglishMode: InputMode = .korean

    /// Callback invoked when mode changes. Set by NRIMEInputController.
    var onModeChanged: ((InputMode) -> Void)?

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
    }
}
