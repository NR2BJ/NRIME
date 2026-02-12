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

        // 2. Japanese conversion state: Mozc manages ALL key handling (including candidates)
        if mode == .japanese && japaneseEngine.isInConversionState {
            return handleJapaneseConversion(event, client: client)
        }

        // 3. Candidate panel navigation (Korean hanja only at this point)
        if let panel = NSApp.candidatePanel, panel.isVisible() {
            return handleCandidateNavigation(event, client: client, panel: panel)
        }

        // 4. Shortcut detection + engine routing
        return routeEvent(event, client: client)
    }

    /// Handle all keyboard events during Japanese Mozc conversion.
    /// Number keys select candidates via Mozc's SELECT_CANDIDATE; all other keys go to JapaneseEngine.
    private func handleJapaneseConversion(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        guard event.type == .keyDown else {
            return japaneseEngine.handleEvent(event, client: client)
        }

        // Number keys 1-9: select candidate and commit the segment
        let numberMap: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
        ]
        if let offset = numberMap[event.keyCode],
           let panel = NSApp.candidatePanel, panel.isVisible() {
            let pageStart = panel.currentPage * panel.effectivePageSize
            let candidateIndex = pageStart + offset
            if candidateIndex < japaneseEngine.mozcConverter.currentCandidates.count {
                if let output = japaneseEngine.mozcConverter.selectCandidateByIndex(candidateIndex) {
                    let result = japaneseEngine.mozcConverter.updateFromOutput(output)
                    japaneseEngine.processMozcResult(result, client: client)
                }
            }
            // After number-key selection, only show panel if there are new candidates
            // (next segment). Otherwise the selection is final.
            if japaneseEngine.isInConversionState
                && !japaneseEngine.mozcConverter.currentCandidateStrings.isEmpty {
                panel.show(candidates: japaneseEngine.mozcConverter.currentCandidateStrings,
                           selectedIndex: japaneseEngine.mozcConverter.currentFocusedIndex,
                           client: client)
            } else {
                panel.hide()
            }
            return true
        }

        // Tab: toggle grid/list mode
        if event.keyCode == 0x30, let panel = NSApp.candidatePanel, panel.isVisible() {
            panel.toggleGridMode(client: client)
            return true
        }

        // Grid mode: intercept arrow keys, Enter, and Escape before Mozc
        if let panel = NSApp.candidatePanel, panel.isGridMode {
            switch event.keyCode {
            case 0x7E: // Up
                panel.moveUpGrid()
                return true
            case 0x7D: // Down
                panel.moveDownGrid()
                return true
            case 0x7B: // Left
                panel.moveLeft()
                return true
            case 0x7C: // Right
                panel.moveRight()
                return true
            case 0x24, 0x4C: // Enter — select via Mozc and commit
                let candidateIndex = panel.selectedIndex
                if candidateIndex < japaneseEngine.mozcConverter.currentCandidates.count {
                    if let output = japaneseEngine.mozcConverter.selectCandidateByIndex(candidateIndex) {
                        let result = japaneseEngine.mozcConverter.updateFromOutput(output)
                        japaneseEngine.processMozcResult(result, client: client)
                    }
                }
                panel.hide()
                return true
            case 0x35: // Escape — forward to Mozc (cancel conversion) and hide panel
                panel.hide()
                _ = japaneseEngine.handleEvent(event, client: client)
                return true
            default:
                break
            }
        }

        // All other keys: forward to JapaneseEngine (which sends to Mozc)
        let handled = japaneseEngine.handleEvent(event, client: client)

        // Update candidate panel from Mozc's current state
        if let panel = NSApp.candidatePanel {
            if !japaneseEngine.mozcConverter.currentCandidateStrings.isEmpty
                && japaneseEngine.isInConversionState {
                panel.show(candidates: japaneseEngine.mozcConverter.currentCandidateStrings,
                           selectedIndex: japaneseEngine.mozcConverter.currentFocusedIndex,
                           client: client)
            } else if panel.isVisible() {
                panel.hide()
            }
        }

        return handled
    }

    /// Handle keyboard events when the candidate panel is visible (Korean hanja only).
    /// Japanese conversion is handled entirely by handleJapaneseConversion() above.
    private func handleCandidateNavigation(_ event: NSEvent, client: any IMKTextInput, panel: CandidatePanel) -> Bool {
        guard event.type == .keyDown else { return false }

        switch event.keyCode {
        case 0x7E: // Up
            if panel.isGridMode {
                panel.moveUpGrid()
            } else {
                panel.moveUp()
            }
            return true

        case 0x7D: // Down
            if panel.isGridMode {
                panel.moveDownGrid()
            } else {
                panel.moveDown()
            }
            return true

        case 0x7B: // Left
            if panel.isGridMode {
                panel.moveLeft()
            } else {
                panel.pageUp()
            }
            return true

        case 0x7C: // Right
            if panel.isGridMode {
                panel.moveRight()
            } else {
                panel.pageDown()
            }
            return true

        case 0x30: // Tab — toggle grid/list mode
            panel.toggleGridMode(client: client)
            return true

        case 0x24, 0x4C: // Return/Enter — select current candidate
            selectCurrentCandidate(client: client, panel: panel)
            return true

        case 0x35: // Escape — dismiss
            panel.hide()
            return true

        case 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19: // Number keys 1-9
            let numberMap: [UInt16: Int] = [
                0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
                0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
            ]
            if let offset = numberMap[event.keyCode] {
                let pageStart = panel.currentPage * panel.effectivePageSize
                let idx = pageStart + offset
                if idx < panel.candidates.count {
                    panel.select(at: idx)
                    selectCurrentCandidate(client: client, panel: panel)
                }
            }
            return true

        case 0x31: // Space — dismiss and pass through for Korean hanja
            panel.hide()
            return false

        default:
            // Dismiss panel and route event through normal handling
            panel.hide()
            return routeEvent(event, client: client)
        }
    }

    /// Select the currently highlighted candidate and commit.
    /// For Japanese: uses Mozc submit() to properly commit multi-segment conversion.
    /// For Korean: commits hanja text directly.
    private func selectCurrentCandidate(client: any IMKTextInput, panel: CandidatePanel) {
        guard let selectedText = panel.currentSelection() else {
            panel.hide()
            return
        }

        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)

        switch StateManager.shared.currentMode {
        case .japanese:
            // Submit through Mozc to properly handle multi-segment state.
            // This is a fallback path — normal Japanese candidate selection goes
            // through handleJapaneseConversion() using SELECT_CANDIDATE.
            if let text = japaneseEngine.mozcConverter.submit() {
                client.insertText(text as NSString, replacementRange: replacementRange)
            } else {
                // Fallback: use panel's selected text if Mozc submit fails
                client.insertText(selectedText as NSString, replacementRange: replacementRange)
            }
            japaneseEngine.exitConversionState()

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
