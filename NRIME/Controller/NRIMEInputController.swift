import Cocoa
import InputMethodKit

@objc(NRIMEInputController)
class NRIMEInputController: IMKInputController {

    private let secureInputDetector = SecureInputDetector()
    private let shortcutHandler = ShortcutHandler()
    private let englishEngine = EnglishEngine()
    private let koreanEngine = KoreanEngine()
    private let japaneseEngine = JapaneseEngine()

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

        let mode = StateManager.shared.currentMode

        // 1. Secure Input: bypass all internal logic
        if secureInputDetector.isSecureInputActive() {
            return false
        }

        // 1.5. Pass through all events when NRIMESettings is the active app
        if client.bundleIdentifier() == "com.nrime.settings" {
            return false
        }

        // 2. Candidate panel navigation (both Japanese and Korean)
        if let panel = NSApp.candidatePanel, panel.isVisible() {
            return handleCandidateNavigation(event, client: client, panel: panel)
        }

        // 3. Japanese conversion state: Mozc manages key handling
        if mode == .japanese && japaneseEngine.isInConversionState {
            return japaneseEngine.handleEvent(event, client: client)
        }

        // 4. Shortcut detection + engine routing
        return routeEvent(event, client: client)
    }

    /// Handle keyboard events when the candidate panel is visible.
    /// Directly controls CandidatePanel selection — no IMKCandidates involved.
    private func handleCandidateNavigation(_ event: NSEvent, client: any IMKTextInput, panel: CandidatePanel) -> Bool {
        guard event.type == .keyDown else { return false }

        switch event.keyCode {
        case 0x7E: // Up
            panel.moveUp()
            updatePreeditFromPanel(panel, client: client)
            return true

        case 0x7D: // Down
            panel.moveDown()
            updatePreeditFromPanel(panel, client: client)
            return true

        case 0x7B: // Left — previous page
            panel.pageUp()
            updatePreeditFromPanel(panel, client: client)
            return true

        case 0x7C: // Right — next page
            panel.pageDown()
            updatePreeditFromPanel(panel, client: client)
            return true

        case 0x24, 0x4C: // Return/Enter — select current candidate
            selectCurrentCandidate(client: client, panel: panel)
            return true

        case 0x35: // Escape — dismiss
            if StateManager.shared.currentMode == .japanese {
                japaneseEngine.mozcConverter.cancel()
                japaneseEngine.exitConversionState()
            }
            panel.hide()
            return true

        case 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19: // Number keys 1-9
            let numberMap: [UInt16: Int] = [
                0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
                0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
            ]
            if let offset = numberMap[event.keyCode] {
                let pageStart = panel.currentPage * panel.pageSize
                let idx = pageStart + offset
                if idx < panel.candidates.count {
                    panel.select(at: idx)
                    selectCurrentCandidate(client: client, panel: panel)
                }
            }
            return true

        case 0x31: // Space — same as Down (next candidate) during conversion
            if StateManager.shared.currentMode == .japanese && japaneseEngine.isInConversionState {
                panel.moveDown()
                updatePreeditFromPanel(panel, client: client)
                return true
            }
            // For Korean hanja, space dismisses and passes through
            panel.hide()
            return false

        default:
            // Dismiss panel and route event through normal handling
            panel.hide()
            if StateManager.shared.currentMode == .japanese && japaneseEngine.isInConversionState {
                return japaneseEngine.handleEvent(event, client: client)
            }
            return routeEvent(event, client: client)
        }
    }

    /// Update preedit (marked text) to show the currently highlighted candidate from the panel.
    /// This keeps the inline text in sync with what the user sees selected in the CandidatePanel,
    /// without forwarding keys to Mozc (which has its own independent selection state).
    private func updatePreeditFromPanel(_ panel: CandidatePanel, client: any IMKTextInput) {
        guard StateManager.shared.currentMode == .japanese,
              japaneseEngine.isInConversionState,
              let text = panel.currentSelection() else { return }

        let attrString = NSAttributedString(string: text, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .markedClauseSegment: 0
        ])
        client.setMarkedText(attrString,
                             selectionRange: NSRange(location: text.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    /// Select the currently highlighted candidate and commit.
    private func selectCurrentCandidate(client: any IMKTextInput, panel: CandidatePanel) {
        guard let selectedText = panel.currentSelection() else {
            panel.hide()
            return
        }

        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)

        switch StateManager.shared.currentMode {
        case .japanese:
            // Always use the panel's selected text directly (not Mozc's internal state)
            // because CandidatePanel selection and Mozc's selection may be out of sync
            // (e.g., after page navigation with ←→).
            japaneseEngine.mozcConverter.cancel()
            japaneseEngine.exitConversionState()
            client.insertText(selectedText as NSString, replacementRange: replacementRange)

        case .korean:
            let hanja = String(selectedText.prefix(while: { $0 != " " }))
            koreanEngine.clearAutomataState()
            // Both composing and selected-text hanja conversions use marked text,
            // so insertText with NSNotFound replaces the current marked text.
            client.insertText(hanja as NSString, replacementRange: replacementRange)

        default:
            break
        }

        panel.hide()
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)

        wireUpShortcutHandler()

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

        // Force commit any composing text
        let client = self.client() as? (any IMKTextInput)
        koreanEngine.forceCommit(client: client)
        japaneseEngine.forceCommit(client: client)
        shortcutHandler.reset()

        // Hide candidate panel
        NSApp.candidatePanel?.hide()

        NSLog("NRIME: deactivateServer")
        super.deactivateServer(sender)
    }

    // MARK: - Event Routing

    /// Route an event through shortcut detection and engine handling.
    /// Shared by handle() and handleCandidateNavigation's default case.
    private func routeEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        if shortcutHandler.onAction == nil {
            wireUpShortcutHandler()
        }
        if shortcutHandler.handleEvent(event) {
            return true
        }
        switch StateManager.shared.currentMode {
        case .english:
            return englishEngine.handleEvent(event, client: client)
        case .korean:
            return koreanEngine.handleEvent(event, client: client)
        case .japanese:
            return japaneseEngine.handleEvent(event, client: client)
        }
    }

    // MARK: - Shortcut Handler Wiring

    private func wireUpShortcutHandler() {
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
                } else if previousMode == .japanese {
                    self.japaneseEngine.forceCommit(client: client)
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
                    return self.koreanEngine.triggerHanjaConversion(client: client)
                }
                return false
            }
        }
    }

}
