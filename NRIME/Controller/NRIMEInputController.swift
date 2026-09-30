import Carbon
import Cocoa
import InputMethodKit

@objc(NRIMEInputController)
class NRIMEInputController: IMKInputController {

    private let secureInputDetector = SecureInputDetector()
    private let shortcutHandler = ShortcutHandler()
    private lazy var englishEngine = EnglishEngine()
    private lazy var koreanEngine = KoreanEngine()
    private lazy var japaneseEngine = JapaneseEngine()

    /// Active controller instance for global mouse monitor callback.
    private static weak var activeController: NRIMEInputController?
    /// Global mouse monitor to commit composing text on click.
    /// IMKit doesn't deliver leftMouseDown through handle(), so we use a global monitor.
    private static var mouseMonitor: Any?
    /// Cached client from the last handle() call. Used by the mouse monitor
    /// because self.client() may be nil by the time the callback fires.
    private var cachedClient: AnyObject?
    /// Last observed secure-input state, so only transitions are logged.
    private var lastSecureInputState = false
    /// Bundle ID of this controller's client, read once at activation so the
    /// developer log never has to ask the host app again mid-keystroke.
    private var activeBundleID: String?
    /// Global monitor recording mouse-button presses for the shortcut handler
    /// (Shift+click is not a Shift tap). Separate from `mouseMonitor` so that
    /// one's commit-on-click behavior is unchanged.
    private static var pointerMonitor: Any?

#if DEBUG
    /// Test seam for controller-level unit tests that run without a real IMK client proxy.
    var testingClientOverride: (any IMKTextInput)?
#endif


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
        let start = ProcessInfo.processInfo.systemUptime
        let modeBefore = StateManager.shared.currentMode
        var trace = EventTrace()
        let consumed = process(event, client: client, trace: &trace)
        logEventTrace(event, start: start, modeBefore: modeBefore, consumed: consumed, trace: trace)
        return consumed
    }

    /// Which path `process` took for an event — for the developer log only.
    private struct EventTrace {
        var path = "engine"
        var sensitive = false
    }

    private func process(_ event: NSEvent, client: any IMKTextInput, trace: inout EventTrace) -> Bool {
        // Keys KeyEventReposter posts come back here like any other and go
        // through the usual path: nothing is composing by then, so the engine
        // passes them on. (A tag in eventSourceUserData was meant to mark them,
        // but it does not survive the trip through IMK.)

        // Cache client for the global mouse monitor callback.
        cachedClient = client as AnyObject

        let mode = StateManager.shared.currentMode

        // 1. Language-switch hotkeys run before any suppression below.
        //    Switching mode types nothing, so nothing about a password field
        //    makes it unsafe — whereas gating it behind secure input locks the
        //    user into whichever mode they were in, for as long as some app
        //    (or a dead process's stale claim) holds the flag. Feeding
        //    flagsChanged here also keeps the handler's modifier tracking in
        //    sync; a release it never sees corrupts the next tap.
        if event.type == .flagsChanged {
            if shortcutHandler.onAction == nil {
                wireUpShortcutHandler()
            }
            if shortcutHandler.handleEvent(event) {
                trace.path = "shortcut"
                return true
            }
        }

        // 2. Secure Input: no composition.
        //    The flag alone is not enough — it can lag the authentication panel
        //    appearing, so also recognize those clients by bundle ID.
        let suppress = secureInputDetector.shouldSuppressComposition()
        if suppress != lastSecureInputState {
            lastSecureInputState = suppress
            logControllerEvent("secureInputChanged", client: client, extra: [
                "suppress": "\(suppress)",
                "holder": secureInputDetector.secureInputHolderBundleID() ?? "unknown"
            ])
        }
        // The bundle ID was read when this client activated; asking the host
        // app again here cost a round trip on every keystroke.
        if suppress
            || secureInputDetector.isAuthenticationClient(activeBundleID ?? client.bundleIdentifier()) {
            // The key still goes to the field, and the shortcut handler must
            // know a key was pressed: otherwise Shift+letter in a password
            // reads as a solo Shift tap and switches the language mid-password
            // (logged in 1Password: two toggles within two seconds of typing).
            shortcutHandler.observeConsumedKeyDown(event)
            trace.path = "secure"
            trace.sensitive = true
            return false
        }

        // 1.5. Pass through all events when NRIMESettings is the active app
        // NRIMESettings: allow normal input (Japanese/Korean) in text fields.
        // Shortcut recording uses its own NSEvent monitor, unaffected by this.

        // 1.7. Preemptive commit on Cmd/Ctrl down (Electron workaround):
        // When Cmd or Ctrl is pressed while composing, commit immediately.
        // This gives Electron time to clear oldHasMarkedText before the
        // actual Cmd+key arrives (which bypasses handle() via performKeyEquivalent).
        if event.type == .flagsChanged {
            let flags = event.modifierFlags
            if flags.contains(.command) || flags.contains(.control) {
                if koreanEngine.isCurrentlyComposing {
                    koreanEngine.forceCommit(client: client)
                }
                if japaneseEngine.isCurrentlyComposing {
                    japaneseEngine.forceCommit(client: client)
                }
            }
        }

        // 2. Japanese conversion state: Mozc manages ALL key handling (including candidates)
        if mode == .japanese && japaneseEngine.isInConversionState {
            shortcutHandler.observeConsumedKeyDown(event)
            trace.path = "conversion"
            return handleJapaneseConversion(event, client: client)
        }

        // 3. Candidate panel navigation (Korean hanja only at this point)
        if let panel = NSApp.candidatePanel, panel.isVisible() {
            shortcutHandler.observeConsumedKeyDown(event)
            trace.path = "candidates"
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
        // (Shift+number is a symbol like ！ — let the engine handle it)
        let numberMap: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
        ]
        if !event.modifierFlags.contains(.shift),
           let offset = numberMap[event.keyCode],
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
            let candidates = japaneseEngine.candidateDisplayStrings
            if japaneseEngine.isInConversionState
                && !candidates.isEmpty {
                panel.show(candidates: candidates,
                           selectedIndex: japaneseEngine.mozcConverter.currentFocusedIndex,
                           client: client)
            } else {
                panel.hide()
            }
            return true
        }

        // Tab: toggle grid/list mode
        if event.keyCode == 0x30, let panel = NSApp.candidatePanel, panel.isVisible() {
            let wasGridMode = panel.isGridMode
            panel.toggleGridMode(client: client)

            // When exiting grid → list, sync panel's selection to Mozc
            if wasGridMode && !panel.isGridMode {
                syncPanelSelectionToMozc(panel: panel, client: client)
            }
            return true
        }

        // List mode, single segment: Left/Right page the candidate list, the
        // same as the hanja list. With several segments they keep Mozc's
        // meaning (move between segments), which multi-segment editing needs.
        if let panel = NSApp.candidatePanel, panel.isVisible(),
           let direction = Self.listModePageDirection(
               keyCode: event.keyCode,
               modifiers: event.modifierFlags,
               segmentCount: japaneseEngine.mozcConverter.currentPreedit?.segment.count ?? 0,
               gridMode: panel.isGridMode
           ) {
            switch direction {
            case .previous: panel.pageUp()
            case .next: panel.pageDown()
            }
            // Keep Mozc on the candidate the panel now shows as selected, so a
            // following Enter commits what the user sees.
            syncPanelSelectionToMozc(panel: panel, client: client)
            return true
        }

        // Grid mode: intercept arrow keys, Enter, and Escape before Mozc
        if let panel = NSApp.candidatePanel, panel.isGridMode {
            switch event.keyCode {
            case 0x7E: // Up
                panel.moveUpGrid()
                syncPanelSelectionToMozc(panel: panel, client: client)
                return true
            case 0x7D: // Down
                panel.moveDownGrid()
                syncPanelSelectionToMozc(panel: panel, client: client)
                return true
            case 0x7B: // Left
                panel.moveLeft()
                syncPanelSelectionToMozc(panel: panel, client: client)
                return true
            case 0x7C: // Right
                panel.moveRight()
                syncPanelSelectionToMozc(panel: panel, client: client)
                return true
            case 0x24, 0x4C: // Enter — highlight selected candidate, then submit all
                let wantsNewline = event.modifierFlags.contains(.shift)
                let candidateIndex = panel.selectedIndex
                if candidateIndex < japaneseEngine.mozcConverter.currentCandidates.count {
                    // Sync highlight to Mozc first (so submit commits the right candidate)
                    _ = japaneseEngine.mozcConverter.highlightCandidateByIndex(candidateIndex)
                }
                let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)
                // Falls back to what is on screen when Mozc gives no result,
                // rather than dropping the word the user explicitly confirmed.
                if let text = japaneseEngine.mozcConverter.commit() {
                    client.insertText(text as NSString, replacementRange: replacementRange)
                }
                japaneseEngine.exitConversionState()
                panel.hide()
                if wantsNewline {
                    return completeShiftEnterNewline(keyCode: event.keyCode, client: client)
                }
                return true
            case 0x35: // Escape — revert to composing
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
            let candidates = japaneseEngine.candidateDisplayStrings
            if !candidates.isEmpty
                && japaneseEngine.isInConversionState {
                panel.show(candidates: candidates,
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
                previewHanjaCandidate(panel: panel, client: client)
            } else {
                panel.moveUp()
            }
            return true

        case 0x7D: // Down
            if panel.isGridMode {
                panel.moveDownGrid()
                previewHanjaCandidate(panel: panel, client: client)
            } else {
                panel.moveDown()
            }
            return true

        case 0x7B: // Left
            if panel.isGridMode {
                panel.moveLeft()
                previewHanjaCandidate(panel: panel, client: client)
            } else {
                panel.pageUp()
            }
            return true

        case 0x7C: // Right
            if panel.isGridMode {
                panel.moveRight()
                previewHanjaCandidate(panel: panel, client: client)
            } else {
                panel.pageDown()
            }
            return true

        case 0x30: // Tab — toggle grid/list mode
            let wasGridMode = panel.isGridMode
            panel.toggleGridMode(client: client)
            if wasGridMode && !panel.isGridMode {
                previewHanjaSourceIfNeeded(client: client)
            }
            return true

        case 0x24, 0x4C: // Return/Enter — select current candidate
            let wantsNewline = event.modifierFlags.contains(.shift)
            selectCurrentCandidate(client: client, panel: panel)
            if wantsNewline {
                return completeShiftEnterNewline(keyCode: event.keyCode, client: client)
            }
            return true

        case 0x35: // Escape — dismiss
            endHanjaSessionIfNeeded(client: client)
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
            let shouldPassThrough = koreanEngine.isCurrentlyComposing
            endHanjaSessionIfNeeded(client: client)
            panel.hide()
            if shouldPassThrough {
                return routeEvent(event, client: client)
            }
            return false

        default:
            // Dismiss panel and route event through normal handling
            endHanjaSessionIfNeeded(client: client)
            panel.hide()
            return routeEvent(event, client: client)
        }
    }

    /// Whether committed text may be written to this client. Authentication
    /// panels never accept composed text, and suppression means no composition
    /// should be landing anywhere.
    private func canCommitText(to client: any IMKTextInput) -> Bool {
        !secureInputDetector.isAuthenticationClient(client.bundleIdentifier())
            && !secureInputDetector.shouldSuppressComposition()
    }

    /// Close a hanja candidate session that something outside the panel is
    /// ending (mode switch, mouse click). Settles the original text first,
    /// while the source is still known, then takes the panel down so it stops
    /// consuming keys meant for the new mode.
    private func endKoreanCandidateSession(client: any IMKTextInput) {
        guard let panel = NSApp.candidatePanel, panel.isVisible() else { return }
        endHanjaSessionIfNeeded(client: client)
        panel.hide()
    }

    /// End the Korean hanja session, committing a selected-text original so the
    /// user's own text can't be replaced by the next keystroke.
    private func endHanjaSessionIfNeeded(client: any IMKTextInput) {
        guard StateManager.shared.currentMode == .korean else { return }
        koreanEngine.endHanjaSession(client: client)
    }

    /// Finish a Shift+Enter that also confirmed a candidate. The newline belongs
    /// to the user's keystroke, not to the candidate list, so the same key means
    /// the same thing whether or not a candidate window happened to be open.
    private func completeShiftEnterNewline(keyCode: UInt16, client: any IMKTextInput) -> Bool {
        if ChromiumDetector.isFrontmostAppChromium {
            KeyEventReposter.performChromiumNewline(keyCode: keyCode, client: client)
            return true
        }
        // Elsewhere the host inserts the newline from the original key event.
        return false
    }

    /// Select the currently highlighted candidate and commit.
    /// For Japanese: submits through Mozc to properly commit multi-segment conversion.
    /// For Korean: commits hanja text directly.
    private func selectCurrentCandidate(client: any IMKTextInput, panel: CandidatePanel) {
        guard let selectedText = panel.currentSelection() else {
            panel.hide()
            return
        }

        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)

        switch StateManager.shared.currentMode {
        case .japanese:
            // Submit through Mozc to properly handle multi-segment state, or
            // commit the panel's selection when Mozc gives no result.
            // This is a fallback path — normal Japanese candidate selection goes
            // through handleJapaneseConversion() using SELECT_CANDIDATE.
            if let text = japaneseEngine.mozcConverter.commit(fallback: selectedText) {
                client.insertText(text as NSString, replacementRange: replacementRange)
            }
            japaneseEngine.exitConversionState()

        case .korean:
            let hanja = String(selectedText.prefix(while: { $0 != " " }))
            koreanEngine.rememberSelectedHanja(hanja)
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

        NRIMEInputController.activeController = self
        InputSourceRecovery.shared.userInitiatedSwitch = false

        // Global mouse monitor: commit composing text on click.
        // Electron apps (Claude Desktop, KakaoTalk) don't reliably call
        // commitComposition/deactivateServer on focus change, so we commit proactively.
        if NRIMEInputController.pointerMonitor == nil {
            NRIMEInputController.pointerMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { event in
                ShortcutHandler.notePointerDown(timestamp: event.timestamp, flags: event.modifierFlags)
            }
        }
        if NRIMEInputController.mouseMonitor == nil {
            NRIMEInputController.mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { _ in
                NRIMEInputController.activeController?.commitOnMouseClick()
            }
        }

        PermissionMonitor.refreshIfStale()

        // Clear any orphaned composing state from previous session.
        // Do NOT use forceCommit here — the previous client may be gone and
        // inserting text into the new client causes duplication ("사과" → "사과과").
        koreanEngine.clearAutomataState()
        japaneseEngine.clearState()

        wireUpShortcutHandler()

        // Wire up mode change callback for inline indicator
        StateManager.shared.onModeChanged = { [weak self] mode in
            if Settings.shared.inlineIndicatorEnabled {
                // Pre-commit position was already captured in shortcutAction.
                // show() will use lastGoodResult which has the accurate pre-commit coords.
                let client = self?.resolvedClient()
                InlineIndicator.shared.show(for: mode, client: client)
            }
        }

        // Restore per-app mode if enabled
        if let client = sender as? (any IMKTextInput) {
            // Cache only a real answer: a controller's client never changes,
            // and a placeholder would stick and mislabel every later log line.
            let bundleId = client.bundleIdentifier()
            if let bundleId { activeBundleID = bundleId }
            StateManager.shared.activateApp(bundleId ?? "unknown")
            logControllerEvent("activateServer", client: client, extra: [
                "bundleID": bundleId ?? "unknown"
            ])
        } else {
            logControllerEvent("activateServer", client: nil)
        }
    }

    override func commitComposition(_ sender: Any!) {
        handleCommitComposition(sender)
        super.commitComposition(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        handleDeactivateServer(sender)
        super.deactivateServer(sender)
    }

    private func handleCommitComposition(_ sender: Any?) {
        if let client = (sender as? (any IMKTextInput))
            ?? resolvedClient() {
            logControllerEvent("commitComposition", client: client)
            koreanEngine.forceCommit(client: client)
            japaneseEngine.forceCommit(client: client)
        }
    }

    private func handleDeactivateServer(_ sender: Any?) {
        // Mark as user-initiated so InputSourceRecovery doesn't fight it
        InputSourceRecovery.shared.userInitiatedSwitch = true

        logControllerEvent("deactivateServer", client: sender as? (any IMKTextInput))

        // Commit composing text — use sender (the client) since self.client()
        // may already be nil during deactivation
        handleCommitComposition(sender)
        shortcutHandler.reset()

        // Hide candidate panel
        NSApp.candidatePanel?.hide()
    }

    // MARK: - Grid/Mozc Sync

    /// Sync the panel's selected candidate index to Mozc using HIGHLIGHT_CANDIDATE.
    /// Called when transitioning from grid mode (panel-only selection) back to Mozc-driven mode.
    /// Uses highlight (not select) to avoid committing the segment.
    enum CandidatePageDirection: Equatable { case previous, next }

    /// Whether Left/Right should page the Japanese candidate list rather than
    /// be forwarded to Mozc as segment-focus movement.
    ///
    /// Only for a single segment: there, segment movement has nowhere to go and
    /// the key visibly did nothing. Shift+Left/Right resizes segments in Mozc
    /// and other modifiers belong to the app, so any modifier opts out; grid
    /// mode has its own two-dimensional navigation.
    static func listModePageDirection(keyCode: UInt16,
                                      modifiers: NSEvent.ModifierFlags,
                                      segmentCount: Int,
                                      gridMode: Bool) -> CandidatePageDirection? {
        guard !gridMode, segmentCount == 1 else { return nil }
        let significant: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        guard modifiers.intersection(significant).isEmpty else { return nil }
        switch keyCode {
        case 0x7B: return .previous
        case 0x7C: return .next
        default: return nil
        }
    }

    private func syncPanelSelectionToMozc(panel: CandidatePanel, client: any IMKTextInput) {
        let candidateIndex = panel.selectedIndex
        guard candidateIndex < japaneseEngine.mozcConverter.currentCandidates.count else { return }

        if let output = japaneseEngine.mozcConverter.highlightCandidateByIndex(candidateIndex) {
            let result = japaneseEngine.mozcConverter.updateFromOutput(output)
            // Update preedit display to reflect the highlighted candidate
            japaneseEngine.processMozcResult(result, client: client)
            // Update panel to show Mozc's synced state
            let candidates = japaneseEngine.candidateDisplayStrings
            if !candidates.isEmpty {
                panel.show(candidates: candidates,
                           selectedIndex: japaneseEngine.mozcConverter.currentFocusedIndex,
                           client: client)
            }
        }
    }

    /// Preview the currently highlighted hanja candidate in the text field.
    /// Shows the hanja character as marked text so the user sees real-time preview in grid mode.
    private func previewHanjaCandidate(panel: CandidatePanel, client: any IMKTextInput) {
        guard StateManager.shared.currentMode == .korean,
              let selectedText = panel.currentSelection() else { return }
        let hanja = String(selectedText.prefix(while: { $0 != " " }))
        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)
        client.setMarkedText(
            hanja as NSString,
            selectionRange: NSRange(location: hanja.count, length: 0),
            replacementRange: replacementRange
        )
    }

    private func previewHanjaSourceIfNeeded(client: any IMKTextInput) {
        guard StateManager.shared.currentMode == .korean else { return }
        koreanEngine.restoreHanjaSource(client: client)
    }

    // MARK: - Mouse Click Commit

    /// Called by the global mouse monitor when a click is detected in any app.
    /// Commits composing text before the click changes focus.
    private func commitOnMouseClick() {
        // Mirror handle()'s gate: a click that lands on (or races with) a
        // secure field must never trigger a commit into it. Uses the same
        // holder-aware rule, so a background app holding the flag does not
        // disable committing everywhere.
        guard !secureInputDetector.shouldSuppressComposition() else { return }

        // Use cached client because self.client() may be nil by the time
        // the async global monitor callback fires.
        guard let client = (cachedClient as? (any IMKTextInput))
                ?? resolvedClient() else { return }
        // Never commit into an authentication panel — the click may well be the
        // one that just raised it.
        guard !secureInputDetector.isAuthenticationClient(client.bundleIdentifier()) else { return }

        // A click ends any candidate session — without this the panel stays
        // visible over stale candidates and hijacks subsequent keys (Enter
        // would insert an old hanja at the new caret). Ending it needs the
        // client: a selected-text session is showing the user's own text as
        // marked text, and dropping the session without settling that leaves it
        // for the next keystroke to overwrite.
        endKoreanCandidateSession(client: client)

        let mode = StateManager.shared.currentMode
        if mode == .korean && koreanEngine.isCurrentlyComposing {
            logControllerEvent("mouseClickCommit", client: client, extra: [
                "reason": "korean_composition"
            ])
            koreanEngine.forceCommit(client: client)
        } else if mode == .japanese
                    && (japaneseEngine.isCurrentlyComposing || japaneseEngine.isInConversionState) {
            logControllerEvent("mouseClickCommit", client: client, extra: [
                "reason": japaneseEngine.isInConversionState ? "japanese_conversion" : "japanese_composition"
            ])
            japaneseEngine.forceCommit(client: client)
        }
    }

    // MARK: - Event Routing

    /// Route an event through shortcut detection and engine handling.
    /// Shared by handle() and handleCandidateNavigation's default case.
    private func routeEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        if shortcutHandler.onAction == nil {
            wireUpShortcutHandler()
        }
        // flagsChanged was already fed to the shortcut handler in handle() step
        // 1.9 — feeding it twice would corrupt the press/release tracking.
        if event.type != .flagsChanged, shortcutHandler.handleEvent(event) {
            return true
        }

        let routedEvent = event

        switch StateManager.shared.currentMode {
        case .english:
            return englishEngine.handleEvent(routedEvent, client: client)
        case .korean:
            return koreanEngine.handleEvent(routedEvent, client: client)
        case .japanese:
            return japaneseEngine.handleEvent(routedEvent, client: client)
        }
    }

    // MARK: - Shortcut Handler Wiring

    private func wireUpShortcutHandler() {
        shortcutHandler.isSensitiveContext = { [weak self] in
            self?.isInSensitiveField() ?? false
        }
        shortcutHandler.isComposingKorean = { [weak self] in
            self?.koreanEngine.isCurrentlyComposing ?? false
        }

        // Tap-hold buffering replay: a letter the handler consumed while the
        // tap modifier was held is now settled — route it to the current mode.
        shortcutHandler.onReplay = { [weak self] original, keepShift in
            guard let self, let client = self.resolvedClient() else { return }
            guard !self.secureInputDetector.shouldSuppressComposition() else { return }
            let event = keepShift ? original : Self.strippingShift(original)
            switch StateManager.shared.currentMode {
            case .korean:
                _ = self.koreanEngine.handleEvent(event, client: client)
            case .japanese:
                _ = self.japaneseEngine.handleEvent(event, client: client)
            case .english:
                // EnglishEngine passes keys through to the system, but a
                // buffered event was already consumed — insert directly.
                if let chars = event.characters, !chars.isEmpty {
                    client.insertText(chars as NSString,
                                      replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                }
            }
        }

        shortcutHandler.onAction = { [weak self] action in
            guard let self = self else { return false }
            // Actions run inside handle(), which just recorded the event's own
            // client. self.client() can be nil around activation changes, and
            // treating that as "no switch" silently dropped the user's tap —
            // the mode is global and never needed a client to change.
            let proxy = self.resolvedClient()
            let client = proxy ?? (self.cachedClient as? (any IMKTextInput))
            if proxy == nil {
                // Nothing shows this happens during handle(); record it if it does.
                self.logControllerEvent("shortcutAction.clientFallback", client: client, extra: [
                    "action": String(describing: action),
                    "hasEventClient": "\(client != nil)"
                ])
            }
            let previousMode = StateManager.shared.currentMode

            switch action {
            case .toggleEnglish, .toggleNonEnglish:
                // Switching modes is always allowed, but the text of a
                // composition that belongs to another field is not: by the time
                // this runs the client may already be an authentication panel,
                // and committing there types the previous field's characters
                // into a password box. Leave it pending instead — it still
                // commits when a normal field is focused again.
                let commitStart = ProcessInfo.processInfo.systemUptime
                if let client, self.canCommitText(to: client) {
                    self.endKoreanCandidateSession(client: client)
                    if previousMode == .korean {
                        self.koreanEngine.forceCommit(client: client)
                    } else if previousMode == .japanese {
                        self.japaneseEngine.forceCommit(client: client)
                    }
                }
                let switchStart = ProcessInfo.processInfo.systemUptime
                switch action {
                case .toggleEnglish:    StateManager.shared.toggleEnglish()
                case .toggleNonEnglish: StateManager.shared.toggleNonEnglish()
                default: break
                }
                let switchEnd = ProcessInfo.processInfo.systemUptime
                // commitMs: settling the old mode's text (Mozc submit for
                // Japanese). switchMs: the mode change, including the inline
                // indicator asking the host app where the caret is.
                self.logControllerEvent("shortcutAction", client: client, extra: [
                    "action": String(describing: action),
                    "previousMode": previousMode.label,
                    "currentMode": StateManager.shared.currentMode.label,
                    "commitMs": String(format: "%.1f", (switchStart - commitStart) * 1000),
                    "switchMs": String(format: "%.1f", (switchEnd - switchStart) * 1000),
                ])
                return true

            case .hanjaConvert:
                // Unlike a mode switch, this reads the selection and inserts
                // text, so it stays behind the suppression check.
                guard let client,
                      !self.secureInputDetector.shouldSuppressComposition() else { return false }
                if StateManager.shared.currentMode == .korean {
                    return self.koreanEngine.triggerHanjaConversion(client: client)
                }
                return false
            }
        }
    }

    /// Rebuild a buffered keyDown without its Shift so the replayed letter
    /// produces the base character (ㄱ not ㄲ, "a" not "A") in the new mode.
    private static func strippingShift(_ event: NSEvent) -> NSEvent {
        // Clear .shift plus both device-dependent shift bits (L 0x2 / R 0x4).
        let stripped = NSEvent.ModifierFlags(
            rawValue: event.modifierFlags.rawValue
                & ~NSEvent.ModifierFlags.shift.rawValue & ~0x6)
        let lowered = (event.charactersIgnoringModifiers ?? event.characters ?? "").lowercased()
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: stripped,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: lowered,
            charactersIgnoringModifiers: lowered,
            isARepeat: false,
            keyCode: event.keyCode
        ) ?? event
    }

    private func logControllerEvent(
        _ event: String,
        client: (any IMKTextInput)?,
        extra: [String: String] = [:]
    ) {
        // Checked first: the bundle ID below is a call into the host app, and
        // this runs inside key handling (mode switches, secure-input changes).
        guard DeveloperLogger.shared.isEnabled else { return }
        if activeBundleID == nil, let asked = client?.bundleIdentifier() {
            activeBundleID = asked
        }
        var metadata = extra
        metadata["bundleID"] = metadata["bundleID"] ?? activeBundleID ?? "unknown"
        metadata["mode"] = StateManager.shared.currentMode.label
        metadata["ctl"] = String(shortcutHandler.diagID)
        DeveloperLogger.shared.log("Controller", event, metadata: metadata)
    }

    /// Developer log: one line per key event, so a lost or late switch can be
    /// reconstructed afterwards from what actually arrived and what it did.
    /// The owner allowed recording keys; inside a password or authentication
    /// field only a mode change is recorded, without key timing.
    /// `lagMs`: how long after the key physically moved this handler started —
    /// host app and IMKit delivery plus anything queued ahead on this thread.
    /// `costMs`: how long this handler then took. Both on the NSEvent.timestamp clock.
    private func logEventTrace(_ event: NSEvent, start: TimeInterval, modeBefore: InputMode,
                               consumed: Bool, trace: EventTrace) {
        guard DeveloperLogger.shared.isEnabled else { return }
        let modeAfter = StateManager.shared.currentMode
        let mode = modeAfter == modeBefore ? modeAfter.label : "\(modeBefore.label)→\(modeAfter.label)"
        let isFlags = event.type == .flagsChanged

        if trace.sensitive || isInSensitiveField() {
            guard modeAfter != modeBefore else { return }
            DeveloperLogger.shared.log("Key", isFlags ? "flags" : "down", metadata: [
                "path": trace.path, "mode": mode, "secure": "Y",
                "ctl": String(shortcutHandler.diagID),
            ])
            return
        }

        var metadata = [
            "key": String(format: "0x%02X", event.keyCode),
            "flags": String(format: "0x%X", event.modifierFlags.rawValue),
            "ts": String(format: "%.3f", event.timestamp),
            "consumed": consumed ? "Y" : "N",
            "path": trace.path,
            "mode": mode,
            "ctl": String(shortcutHandler.diagID),
            "bundleID": activeBundleID ?? "unknown",
            "costMs": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - start) * 1000),
        ]
        let lag = start - event.timestamp
        if event.timestamp > 0, lag >= 0, lag < 10 {
            metadata["lagMs"] = String(format: "%.1f", lag * 1000)
        }
        // isARepeat is only valid for key events; flagsChanged would throw.
        if !isFlags, event.isARepeat {
            metadata["repeat"] = "Y"
        }
        DeveloperLogger.shared.log("Key", isFlags ? "flags" : "down", metadata: metadata)
    }

    /// For log redaction only: secure input is on, or this controller's client
    /// is authentication UI. Cheap — a flag read and the cached bundle ID, no
    /// registry lookup and no call into the host app.
    private func isInSensitiveField() -> Bool {
        SecureInputDetector.isSystemSecureInputOn || secureInputDetector.isAuthenticationClient(activeBundleID)
    }

    private func resolvedClient() -> (any IMKTextInput)? {
#if DEBUG
        if let testingClientOverride {
            return testingClientOverride
        }
#endif
        return self.client()
    }

#if DEBUG
    func commitCompositionForTesting(sender: Any?) {
        handleCommitComposition(sender)
    }

    func deactivateServerForTesting(sender: Any?) {
        handleDeactivateServer(sender)
    }

    func commitOnMouseClickForTesting() {
        commitOnMouseClick()
    }
#endif

}
