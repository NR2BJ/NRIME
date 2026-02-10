import Cocoa
import InputMethodKit

@objc(NRIMEInputController)
class NRIMEInputController: IMKInputController {

    private let secureInputDetector = SecureInputDetector()
    private let shortcutHandler = ShortcutHandler()
    private let englishEngine = EnglishEngine()
    private let koreanEngine = KoreanEngine()

    // MARK: - IMKInputController Overrides

    override func recognizedEvents(_ sender: Any!) -> Int {
        let mask = NSEvent.EventTypeMask.keyDown
            .union(.flagsChanged)
        return Int(mask.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event,
              let client = sender as? (any IMKTextInput) else {
            return false
        }

        // 1. Secure Input: bypass all internal logic
        if secureInputDetector.isSecureInputActive() {
            return false
        }

        // 2. Shortcut detection (Right Shift tap, etc.)
        //    On mode change, commit any composing Korean text first
        let previousMode = StateManager.shared.currentMode
        if shortcutHandler.handleEvent(event) {
            if previousMode == .korean {
                koreanEngine.forceCommit(client: client)
            }
            return true
        }

        // 3. Route to active engine based on current mode
        switch StateManager.shared.currentMode {
        case .english:
            return englishEngine.handleEvent(event, client: client)
        case .korean:
            return koreanEngine.handleEvent(event, client: client)
        case .japanese:
            return false // Phase 4
        }
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)

        // Wire up mode change callback to show inline indicator
        StateManager.shared.onModeChanged = { [weak self] mode in
            let client = self?.client() as? (any IMKTextInput)
            InlineIndicator.shared.show(for: mode, client: client)
        }

        NSLog("NRIME: activateServer — mode: \(StateManager.shared.currentMode.label)")
    }

    override func deactivateServer(_ sender: Any!) {
        // Force commit any composing Korean text
        let client = self.client() as? (any IMKTextInput)
        koreanEngine.forceCommit(client: client)
        shortcutHandler.reset()
        NSLog("NRIME: deactivateServer")
        super.deactivateServer(sender)
    }

    // MARK: - IMKCandidates Support

    override func candidates(_ sender: Any!) -> [Any]! {
        return koreanEngine.hanjaConverter?.currentCandidateStrings ?? []
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = self.client() as? (any IMKTextInput),
              let selectedText = candidateString?.string else { return }

        // Extract the hanja character (first character before the space/meaning)
        let hanja = String(selectedText.prefix(while: { $0 != " " }))
        client.insertText(hanja as NSString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }
}
