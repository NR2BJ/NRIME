import Cocoa
import InputMethodKit

@objc(NRIMEInputController)
class NRIMEInputController: IMKInputController {

    private let secureInputDetector = SecureInputDetector()
    private let shortcutHandler = ShortcutHandler()
    private let englishEngine = EnglishEngine()
    private let koreanEngine = KoreanEngine()

    /// Track current candidate selection index (interpretKeyEvents doesn't update selectedCandidate())
    private var candidateSelectionIndex: Int = 0

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

        let clientBundleId = client.bundleIdentifier() ?? "unknown"

        // 1. Secure Input: bypass all internal logic
        if secureInputDetector.isSecureInputActive() {
            return false
        }

        // 1.5. Pass through all events when NRIMESettings is the active app
        if clientBundleId == "com.nrime.inputmethod.settings" {
            return false
        }

        // 2. Hanja candidate window navigation
        if let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.candidatesWindow.isVisible() {
            return handleCandidateNavigation(event, client: client, candidates: appDelegate.candidatesWindow)
        }

        // 3. Shortcut detection (all configurable shortcuts)
        if shortcutHandler.handleEvent(event) {
            return true
        }

        // 4. Route to active engine based on current mode
        switch StateManager.shared.currentMode {
        case .english:
            return englishEngine.handleEvent(event, client: client)
        case .korean:
            return koreanEngine.handleEvent(event, client: client)
        case .japanese:
            return false // Phase 4
        }
    }

    /// Handle keyboard events when the Hanja candidate window is visible.
    /// All navigation is tracked via candidateSelectionIndex; IMKCandidates only used for display.
    private func handleCandidateNavigation(_ event: NSEvent, client: any IMKTextInput, candidates: IMKCandidates) -> Bool {
        guard event.type == .keyDown else { return false }

        let candidateList = koreanEngine.hanjaConverter?.currentCandidateStrings ?? []
        let count = candidateList.count

        switch event.keyCode {
        case 0x7E: // Up — move selection up by 1
            if candidateSelectionIndex > 0 { candidateSelectionIndex -= 1 }
            candidates.interpretKeyEvents([event])
            return true
        case 0x7D: // Down — move selection down by 1
            if candidateSelectionIndex < count - 1 { candidateSelectionIndex += 1 }
            candidates.interpretKeyEvents([event])
            return true
        case 0x7B: // Left — previous page
            candidateSelectionIndex = max(0, candidateSelectionIndex - 9)
            candidates.interpretKeyEvents([event])
            return true
        case 0x7C: // Right — next page
            candidateSelectionIndex = min(candidateSelectionIndex + 9, count - 1)
            candidates.interpretKeyEvents([event])
            return true
        case 0x24, 0x4C: // Return/Enter — select current candidate
            if candidateSelectionIndex >= 0 && candidateSelectionIndex < count {
                candidateSelected(NSAttributedString(string: candidateList[candidateSelectionIndex]))
            } else {
                candidates.hide()
            }
            return true
        case 0x35: // Escape — dismiss
            candidates.hide()
            return true
        case 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19: // Number keys 1-9
            let numberMap: [UInt16: Int] = [
                0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
                0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
            ]
            if let offset = numberMap[event.keyCode] {
                let pageStart = (candidateSelectionIndex / 9) * 9
                let idx = pageStart + offset
                if idx < count {
                    candidateSelectionIndex = idx
                    candidateSelected(NSAttributedString(string: candidateList[idx]))
                }
            }
            return true
        default:
            candidates.hide()
            if shortcutHandler.handleEvent(event) {
                return true
            }
            switch StateManager.shared.currentMode {
            case .english:
                return englishEngine.handleEvent(event, client: client)
            case .korean:
                return koreanEngine.handleEvent(event, client: client)
            case .japanese:
                return false
            }
        }
    }


    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)

        // Wire up shortcut action handler (uses self.client() for fresh reference)
        shortcutHandler.onAction = { [weak self] action in
            guard let self = self,
                  let client = self.client() as? (any IMKTextInput) else {
                return false
            }
            let previousMode = StateManager.shared.currentMode

            switch action {
            case .toggleEnglish, .switchKorean, .switchJapanese:
                if previousMode == .korean {
                    self.koreanEngine.forceCommit(client: client)
                }
                switch action {
                case .toggleEnglish: StateManager.shared.toggleEnglish()
                case .switchKorean:  StateManager.shared.switchTo(.korean)
                case .switchJapanese: StateManager.shared.switchTo(.japanese)
                default: break
                }
                return true

            case .hanjaConvert:
                if StateManager.shared.currentMode == .korean {
                    self.candidateSelectionIndex = 0
                    return self.koreanEngine.triggerHanjaConversion(client: client)
                }
                return false
            }
        }

        // Wire up mode change callback for inline indicator
        StateManager.shared.onModeChanged = { [weak self] mode in
            if Settings.shared.inlineIndicatorEnabled {
                let client = self?.client() as? (any IMKTextInput)
                InlineIndicator.shared.show(for: mode, client: client)
            }
        }

        // Restore per-app mode if enabled
        if let client = sender as? (any IMKTextInput) {
            let bundleId = client.bundleIdentifier() ?? "unknown"
            StateManager.shared.activateApp(bundleId)
            NSLog("NRIME: activateServer — mode: \(StateManager.shared.currentMode.label), app: \(bundleId)")
        } else {
            NSLog("NRIME: activateServer — mode: \(StateManager.shared.currentMode.label)")
        }
    }

    override func deactivateServer(_ sender: Any!) {
        // Save per-app mode if enabled
        if let client = sender as? (any IMKTextInput) {
            let bundleId = client.bundleIdentifier() ?? "unknown"
            StateManager.shared.deactivateApp(bundleId)
        }

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

        let hanja = String(selectedText.prefix(while: { $0 != " " }))

        if let converter = koreanEngine.hanjaConverter, converter.isSelectedTextConversion {
            // Selected text conversion: replace the original selected range
            client.insertText(hanja as NSString, replacementRange: converter.selectedTextRange)
            converter.isSelectedTextConversion = false
            converter.selectedTextRange = NSRange(location: NSNotFound, length: NSNotFound)
        } else {
            // Composing text conversion: flush automata state first, then replace marked text
            koreanEngine.clearAutomataState()
            client.insertText(hanja as NSString, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }

        // Dismiss candidate window after selection
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.candidatesWindow.hide()
        }
    }
}
