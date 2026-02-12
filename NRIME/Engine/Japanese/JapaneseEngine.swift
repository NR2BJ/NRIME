import Cocoa
import InputMethodKit

/// Japanese input engine conversion state.
private enum ConversionState {
    /// User is typing romaji, RomajiComposer is active.
    case composing
    /// After Space/conversion, Mozc has active segments.
    case converting
}

final class JapaneseEngine: InputEngine {
    private let composer = RomajiComposer()
    let mozcConverter = MozcConverter()
    private let backspaceKeyCode: UInt16 = 0x33

    private var conversionState: ConversionState = .composing

    /// Tracks whether the current composing text should be committed as katakana (Shift+katakana mode).
    private var shiftKatakanaActive = false
    /// Tracks whether Caps Lock katakana mode is active (for commitComposing to use).
    private var capsLockKatakanaActive = false

    /// Whether live conversion is currently active (Mozc has been fed characters during composing).
    private var liveConversionActive = false

    /// The last peeked conversion text from live conversion (for commitLiveConversion).
    private var liveConvertedText: String? = nil

    /// Whether prediction candidates are currently displayed after a commit.
    private(set) var showingPrediction = false

    /// Whether the engine is in Mozc conversion state (for controller routing).
    var isInConversionState: Bool {
        conversionState == .converting || showingPrediction
    }

    // MARK: - InputEngine

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        // Handle Caps Lock (flagsChanged) for Japanese-specific behavior
        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: client)
        }

        guard event.type == .keyDown else { return false }

        // Ignore events with Command, Control, or Option modifiers
        let mods = event.modifierFlags
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            if showingPrediction {
                dismissPrediction()
            }
            if conversionState == .converting {
                commitConversion(client: client)
            } else {
                commitComposing(client: client)
            }
            return false
        }

        switch conversionState {
        case .composing:
            return handleComposingEvent(event, client: client)
        case .converting:
            return handleConvertingEvent(event, client: client)
        }
    }

    func reset(client: any IMKTextInput) {
        if showingPrediction {
            dismissPrediction()
        }
        if conversionState == .converting {
            commitConversion(client: client)
        } else {
            commitComposing(client: client)
        }
    }

    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client else { return }

        if showingPrediction {
            dismissPrediction()
        }

        if conversionState == .converting {
            if let text = mozcConverter.submit() {
                client.insertText(text as NSString, replacementRange: replacementRange())
            }
            conversionState = .composing
            hideCandidateWindow()
        }

        mozcConverter.reset()
        liveConversionActive = false
        guard composer.isComposing else { return }
        let text = composer.flush()
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    /// Exit conversion state (used by controller after candidate selection).
    func exitConversionState() {
        conversionState = .composing
        mozcConverter.currentCandidateStrings = []
        composer.clear()
        liveConversionActive = false
        liveConvertedText = nil
        showingPrediction = false
        hideCandidateWindow()
    }

    /// Process a MozcResult: update preedit, candidate panel, and conversion state.
    /// Returns true if the result was consumed (caller should swallow the key event).
    @discardableResult
    func processMozcResult(_ result: MozcResult, client: any IMKTextInput) -> Bool {
        // Handle committed text
        if let committed = result.committedText {
            client.insertText(committed as NSString, replacementRange: replacementRange())
            conversionState = .composing
            composer.clear()
            liveConversionActive = false
            hideCandidateWindow()

            // Check if Mozc started a new preedit after commit (next segment)
            if let preedit = result.preedit, !preedit.segment.isEmpty {
                renderPreedit(preedit, client: client)
                conversionState = .converting
                if result.hasCandidates {
                    showCandidateWindow(client: client)
                }
            } else {
                client.setMarkedText("" as NSString,
                                     selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: replacementRange())

                // Trigger prediction after commit if enabled
                triggerPredictionIfEnabled(client: client)
            }
            return true
        }

        // Handle preedit update (segment navigation, candidate change)
        if let preedit = result.preedit {
            if preedit.segment.isEmpty {
                // Mozc cleared the preedit — revert to composing with original hiragana.
                revertToComposing(client: client)
            } else {
                renderPreedit(preedit, client: client)
                if result.hasCandidates {
                    showCandidateWindow(client: client)
                } else {
                    hideCandidateWindow()
                }
            }
            return true
        }

        // No preedit and no committed text — Mozc dropped the conversion.
        // Revert to composing with original hiragana so text isn't lost.
        revertToComposing(client: client)
        return result.consumed
    }

    // MARK: - Flags Changed (Caps Lock)

    private func handleFlagsChanged(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let keyCode = event.keyCode
        let config = Settings.shared.japaneseKeyConfig

        // Only handle Caps Lock with non-default action
        guard keyCode == 0x39, config.capsLockAction != .capsLock else { return false }
        // Only act when composing
        guard composer.isComposing else { return false }

        switch config.capsLockAction {
        case .katakana:
            return sendFunctionKeyToMozc(.f7, client: client)
        case .romaji:
            return sendFunctionKeyToMozc(.f10, client: client)
        case .capsLock:
            return false
        }
    }

    // MARK: - Composing State

    private func handleComposingEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)
        let isCapsLockOn = event.modifierFlags.contains(.capsLock)
        let capsAction = Settings.shared.japaneseKeyConfig.capsLockAction

        // --- Prediction state handling ---
        // When showing prediction candidates, handle selection keys before normal composing.
        if showingPrediction {
            return handlePredictionEvent(event, client: client)
        }

        // Backspace
        if keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Enter — commit composing text
        if keyCode == 0x24 || keyCode == 0x4C {
            let wasComposing = composer.isComposing
            if liveConversionActive {
                commitLiveConversion(client: client)
            } else {
                commitComposing(client: client)
            }
            // Shift+Enter while composing: re-post via CGEvent (same as Korean).
            if wasComposing && isShifted {
                Self.repostShiftEnter(keyCode: keyCode)
                return true
            }
            return wasComposing
        }

        // Space — trigger Mozc conversion, or insert full-width space
        if keyCode == 0x31 {
            if composer.isComposing {
                return triggerMozcConversion(client: client)
            }
            // Not composing: insert full-width space if configured
            if Settings.shared.japaneseKeyConfig.fullWidthSpace {
                client.insertText("\u{3000}" as NSString, replacementRange: replacementRange())
                return true
            }
            return false
        }

        // Down arrow while composing — also trigger conversion
        if keyCode == 0x7D && composer.isComposing {
            return triggerMozcConversion(client: client)
        }

        // Escape — cancel composing
        if keyCode == 0x35 {
            if composer.isComposing {
                if liveConversionActive {
                    mozcConverter.cancel()
                    liveConversionActive = false
                    liveConvertedText = nil
                }
                composer.clear()
                client.setMarkedText("" as NSString,
                                     selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: replacementRange())
                return true
            }
            return false
        }

        // Configurable Japanese IME keys (F6-F10 by default) — while composing
        if composer.isComposing, let specialKey = japaneseIMEKeyToSpecialKey(keyCode) {
            return sendFunctionKeyToMozc(specialKey, client: client)
        }

        // Arrow keys, Tab, etc. — commit and pass through
        if keyCode == 0x7E || keyCode == 0x7B || keyCode == 0x7C || keyCode == 0x30 {
            if liveConversionActive {
                commitLiveConversion(client: client)
            } else {
                commitComposing(client: client)
            }
            return false
        }

        // Punctuation, slash, yen — configurable Japanese symbol handling (only without Shift)
        if !isShifted, let symbol = symbolForKeyCode(keyCode) {
            if liveConversionActive {
                commitLiveConversion(client: client)
            } else {
                commitComposing(client: client)
            }
            client.insertText(symbol as NSString, replacementRange: replacementRange())
            return true
        }

        // Alphabetic input -> romaji composition
        if let char = Self.charForKeyCode(keyCode, shifted: isShifted) {
            let shiftAction = Settings.shared.japaneseKeyConfig.shiftKeyAction

            // Caps Lock romaji: insert the character directly (bypass romaji->kana)
            if isCapsLockOn && capsAction == .romaji {
                if liveConversionActive {
                    commitLiveConversion(client: client)
                } else {
                    commitComposing(client: client)
                }
                client.insertText(String(char) as NSString, replacementRange: replacementRange())
                return true
            }

            // Shift+key with romaji action: insert the character directly (bypass romaji->kana)
            if isShifted && shiftAction == .romaji {
                if liveConversionActive {
                    commitLiveConversion(client: client)
                } else {
                    commitComposing(client: client)
                }
                client.insertText(String(char) as NSString, replacementRange: replacementRange())
                return true
            }

            // Track caps-lock-katakana state (for commitComposing)
            capsLockKatakanaActive = isCapsLockOn && capsAction == .katakana

            // Track shift-katakana state
            if isShifted && shiftAction == .katakana {
                shiftKatakanaActive = true
            } else if !isShifted {
                shiftKatakanaActive = false
            }

            let result = composer.input(char)
            var display = result.composing + result.pending

            // Show katakana while shift-katakana or caps-lock-katakana is active
            if shiftKatakanaActive || capsLockKatakanaActive {
                display = hiraganaToKatakana(display)
            }

            // --- Live conversion ---
            let liveEnabled = Settings.shared.japaneseKeyConfig.liveConversion
            if liveEnabled
                && !shiftKatakanaActive && !capsLockKatakanaActive
                && !composer.composedKana.isEmpty {
                updateLiveConversion(pending: composer.pendingRomaji, client: client)
                return true
            }

            // Normal display (no live conversion)
            if display.isEmpty {
                client.setMarkedText("" as NSString,
                                     selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: replacementRange())
            } else {
                client.setMarkedText(display as NSString,
                                     selectionRange: NSRange(location: display.count, length: 0),
                                     replacementRange: replacementRange())
            }
            return true
        }

        // Non-alpha key — commit composing and pass through
        if liveConversionActive {
            commitLiveConversion(client: client)
        } else {
            commitComposing(client: client)
        }
        return false
    }

    // MARK: - Prediction Handling

    /// Handle key events while prediction candidates are visible.
    private func handlePredictionEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)

        // Tab — select the current prediction candidate and commit
        if keyCode == 0x30 {
            let idx = mozcConverter.currentFocusedIndex
            if idx < mozcConverter.currentCandidates.count {
                if let output = mozcConverter.selectCandidateByIndex(idx) {
                    let result = mozcConverter.updateFromOutput(output)
                    if let committed = result.committedText {
                        client.insertText(committed as NSString, replacementRange: replacementRange())
                    }
                }
            }
            dismissPrediction()
            // After selecting a prediction, trigger next prediction
            triggerPredictionIfEnabled(client: client)
            return true
        }

        // Number keys 1-9 — direct selection
        let numberMap: [UInt16: Int] = [
            0x12: 0, 0x13: 1, 0x14: 2, 0x15: 3, 0x17: 4,
            0x16: 5, 0x1A: 6, 0x1C: 7, 0x19: 8
        ]
        if let offset = numberMap[keyCode] {
            let panel = NSApp.candidatePanel
            let pageStart = (panel?.currentPage ?? 0) * (panel?.effectivePageSize ?? 9)
            let candidateIndex = pageStart + offset
            if candidateIndex < mozcConverter.currentCandidates.count {
                if let output = mozcConverter.selectCandidateByIndex(candidateIndex) {
                    let result = mozcConverter.updateFromOutput(output)
                    if let committed = result.committedText {
                        client.insertText(committed as NSString, replacementRange: replacementRange())
                    }
                }
            }
            dismissPrediction()
            triggerPredictionIfEnabled(client: client)
            return true
        }

        // Escape — dismiss prediction
        if keyCode == 0x35 {
            dismissPrediction()
            return true
        }

        // Enter — dismiss prediction (don't select anything)
        if keyCode == 0x24 || keyCode == 0x4C {
            dismissPrediction()
            // Don't consume — let it pass through if user wants a newline
            return false
        }

        // Up/Down arrows — navigate prediction candidates
        if keyCode == 0x7E { // Up
            NSApp.candidatePanel?.moveUp()
            return true
        }
        if keyCode == 0x7D { // Down
            NSApp.candidatePanel?.moveDown()
            return true
        }

        // Space — dismiss prediction and pass through
        if keyCode == 0x31 {
            dismissPrediction()
            return false
        }

        // Alphabetic input — dismiss prediction and start new composing
        if Self.charForKeyCode(keyCode, shifted: isShifted) != nil {
            dismissPrediction()
            // Re-enter handleComposingEvent with this key
            // (showingPrediction is now false, so it won't recurse)
            return handleComposingEvent(event, client: client)
        }

        // Backspace — dismiss prediction
        if keyCode == backspaceKeyCode {
            dismissPrediction()
            return false
        }

        // Any other key — dismiss prediction and pass through
        dismissPrediction()
        return false
    }

    /// Dismiss the prediction panel and reset prediction state.
    private func dismissPrediction() {
        showingPrediction = false
        mozcConverter.cancel()
        mozcConverter.currentCandidateStrings = []
        hideCandidateWindow()
    }

    /// Trigger prediction after a commit, if the setting is enabled.
    private func triggerPredictionIfEnabled(client: any IMKTextInput) {
        guard Settings.shared.japaneseKeyConfig.prediction else { return }

        // Get preceding text from the client for Mozc's NWP engine.
        // Use up to 20 characters before the cursor.
        var precedingText = ""
        let selRange = client.selectedRange()
        if selRange.location != NSNotFound && selRange.location > 0 {
            let start = max(0, selRange.location - 20)
            let len = selRange.location - start
            let fetchRange = NSRange(location: start, length: len)
            if let attrStr = client.attributedSubstring(from: fetchRange) {
                precedingText = attrStr.string
            }
        }

        if let _ = mozcConverter.requestPrediction(precedingText: precedingText) {
            showingPrediction = true
            showCandidateWindow(client: client)
        }
    }

    // MARK: - Live Conversion

    /// Update the marked text with Mozc's live conversion result.
    /// Called after each alphabetic input when live conversion is enabled.
    ///
    /// Strategy: cancel → feed hiragana → Space (peek conversion) → display kanji.
    /// After peek, Mozc stays in CONVERSION state. Next keystroke will cancel() + re-feed.
    private func updateLiveConversion(pending: String, client: any IMKTextInput) {
        let kana = composer.composedKana

        // Cancel any previous Mozc state and re-feed the full hiragana
        mozcConverter.cancel()
        guard mozcConverter.feedHiragana(kana) else {
            liveConversionActive = false
            liveConvertedText = nil
            let display = kana + pending
            client.setMarkedText(display as NSString,
                                 selectionRange: NSRange(location: display.count, length: 0),
                                 replacementRange: replacementRange())
            return
        }

        // Trigger CONVERSION — preedit now contains kanji segments.
        // Session stays in CONVERSION state (not reverted).
        let convertedText = mozcConverter.peekConversion()

        liveConversionActive = true
        liveConvertedText = convertedText

        if let converted = convertedText, converted != kana {
            // Thin underline for live conversion (vs thick for .converting state)
            let attrString = NSMutableAttributedString()

            let convertedAttr = NSAttributedString(string: converted, attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .markedClauseSegment: 0
            ])
            attrString.append(convertedAttr)

            if !pending.isEmpty {
                let pendingAttr = NSAttributedString(string: pending, attributes: [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .markedClauseSegment: 1
                ])
                attrString.append(pendingAttr)
            }

            client.setMarkedText(attrString,
                                 selectionRange: NSRange(location: attrString.length, length: 0),
                                 replacementRange: replacementRange())
        } else {
            // No conversion result — show hiragana normally
            let display = kana + pending
            client.setMarkedText(display as NSString,
                                 selectionRange: NSRange(location: display.count, length: 0),
                                 replacementRange: replacementRange())
        }
    }

    /// Commit the current live conversion result.
    /// Uses the peeked conversion text from the last updateLiveConversion call.
    private func commitLiveConversion(client: any IMKTextInput) {
        guard composer.isComposing else { return }

        if liveConversionActive {
            // Use the stored peeked conversion text
            let commitText = liveConvertedText
            if let text = commitText, !text.isEmpty {
                client.insertText(text as NSString, replacementRange: replacementRange())
            } else {
                var text = composer.flush()
                if shiftKatakanaActive || capsLockKatakanaActive {
                    text = hiraganaToKatakana(text)
                    shiftKatakanaActive = false
                }
                if !text.isEmpty {
                    client.insertText(text as NSString, replacementRange: replacementRange())
                }
            }
        } else {
            // Not live converting — commit hiragana normally
            var text = composer.flush()
            if shiftKatakanaActive || capsLockKatakanaActive {
                text = hiraganaToKatakana(text)
                shiftKatakanaActive = false
            }
            if !text.isEmpty {
                client.insertText(text as NSString, replacementRange: replacementRange())
            }
        }

        composer.clear()
        liveConversionActive = false
        liveConvertedText = nil
        mozcConverter.reset()

        // Trigger prediction after commit
        triggerPredictionIfEnabled(client: client)
    }

    // MARK: - Converting State (Mozc key forwarding)

    private func handleConvertingEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)

        // Shift+Enter — commit conversion then re-post via CGEvent.
        if (keyCode == 0x24 || keyCode == 0x4C) && isShifted {
            commitConversion(client: client)
            Self.repostShiftEnter(keyCode: keyCode)
            return true
        }

        // Escape — revert to hiragana composing state (not Mozc converting).
        // This returns to .composing with the original hiragana in the composer,
        // so Backspace works naturally (one char at a time, no ghost text).
        if keyCode == 0x35 {
            revertToComposing(client: client)
            return true
        }

        // Build Mozc KeyEvent from NSEvent
        guard let mozcKey = buildMozcKeyEvent(keyCode: keyCode, shifted: isShifted) else {
            // Unknown key — commit conversion and pass through
            commitConversion(client: client)
            return false
        }

        // Send to Mozc
        guard let output = mozcConverter.sendKeyEvent(mozcKey) else {
            // IPC error — commit whatever we have
            commitConversion(client: client)
            return false
        }

        // Process Mozc's response
        let result = mozcConverter.updateFromOutput(output)
        return processMozcResult(result, client: client)
    }

    // MARK: - Conversion Helpers

    private func triggerMozcConversion(client: any IMKTextInput) -> Bool {
        if liveConversionActive {
            // Live conversion active — Mozc is already in CONVERSION state from peekConversion().
            // Transition to .converting and show candidate window.
            let hiragana = composer.flush()
            guard !hiragana.isEmpty else { return false }

            mozcConverter.originalHiragana = hiragana
            conversionState = .converting
            liveConversionActive = false
            liveConvertedText = nil

            if let preedit = mozcConverter.currentPreedit, !preedit.segment.isEmpty {
                renderPreedit(preedit, client: client)
                showCandidateWindow(client: client)
                return true
            }

            // Fallback: peekConversion didn't leave valid state — do full convert
            mozcConverter.cancel()
            if mozcConverter.convert(hiragana: hiragana) {
                if let preedit = mozcConverter.currentPreedit, !preedit.segment.isEmpty {
                    renderPreedit(preedit, client: client)
                } else {
                    client.setMarkedText(hiragana as NSString,
                                         selectionRange: NSRange(location: hiragana.count, length: 0),
                                         replacementRange: replacementRange())
                }
                showCandidateWindow(client: client)
                return true
            }

            // Mozc completely unavailable — commit hiragana
            client.insertText(hiragana as NSString, replacementRange: replacementRange())
            return true
        }

        // Normal (non-live) conversion path
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }

        if mozcConverter.convert(hiragana: hiragana) {
            conversionState = .converting

            // Render Mozc's multi-segment preedit if available, otherwise show hiragana
            if let preedit = mozcConverter.currentPreedit, !preedit.segment.isEmpty {
                renderPreedit(preedit, client: client)
            } else {
                client.setMarkedText(hiragana as NSString,
                                     selectionRange: NSRange(location: hiragana.count, length: 0),
                                     replacementRange: replacementRange())
            }

            showCandidateWindow(client: client)
            return true
        }

        // Mozc unavailable or no candidates — commit hiragana directly
        client.insertText(hiragana as NSString, replacementRange: replacementRange())
        return true
    }

    /// Send a configurable Japanese IME key (F6-F10) to Mozc during composing state.
    private func sendFunctionKeyToMozc(_ specialKey: Mozc_Commands_KeyEvent.SpecialKey,
                                       client: any IMKTextInput) -> Bool {
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }

        // If live conversion is active, Mozc is in CONVERSION state from peekConversion.
        // Cancel and re-feed so the function key works from SUGGESTION state.
        if liveConversionActive {
            liveConversionActive = false
            liveConvertedText = nil
            mozcConverter.cancel()
            guard mozcConverter.feedHiragana(hiragana) else {
                client.insertText(hiragana as NSString, replacementRange: replacementRange())
                return true
            }
        } else {
            guard mozcConverter.feedHiragana(hiragana) else {
                client.insertText(hiragana as NSString, replacementRange: replacementRange())
                return true
            }
        }

        var keyEvent = Mozc_Commands_KeyEvent()
        keyEvent.specialKey = specialKey

        guard let output = mozcConverter.sendKeyEvent(keyEvent) else {
            client.insertText(hiragana as NSString, replacementRange: replacementRange())
            return true
        }

        let result = mozcConverter.updateFromOutput(output)

        if let committed = result.committedText {
            client.insertText(committed as NSString, replacementRange: replacementRange())
            return true
        }

        if let preedit = result.preedit, !preedit.segment.isEmpty {
            conversionState = .converting
            renderPreedit(preedit, client: client)
            if result.hasCandidates {
                showCandidateWindow(client: client)
            }
        } else {
            // F-key didn't produce preedit — commit hiragana as fallback
            client.insertText(hiragana as NSString, replacementRange: replacementRange())
        }

        return true
    }

    /// Revert from converting state back to composing with the original hiragana.
    /// Called when user presses Escape during conversion.
    /// Restores hiragana to the composer so Backspace works naturally.
    private func revertToComposing(client: any IMKTextInput) {
        let hiragana = mozcConverter.originalHiragana
        mozcConverter.cancel()
        mozcConverter.reset()
        conversionState = .composing
        liveConversionActive = false
        liveConvertedText = nil
        hideCandidateWindow()

        if hiragana.isEmpty {
            composer.clear()
            client.setMarkedText("" as NSString,
                                 selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: replacementRange())
        } else {
            // Restore hiragana into the composer so Backspace/editing works
            composer.restore(kana: hiragana)
            client.setMarkedText(hiragana as NSString,
                                 selectionRange: NSRange(location: hiragana.count, length: 0),
                                 replacementRange: replacementRange())
        }
    }

    private func commitConversion(client: any IMKTextInput) {
        if let text = mozcConverter.submit() {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
        conversionState = .composing
        composer.clear()
        liveConversionActive = false
        hideCandidateWindow()

        // Trigger prediction after commit
        triggerPredictionIfEnabled(client: client)
    }

    private func commitComposing(client: any IMKTextInput) {
        guard composer.isComposing else { return }

        if liveConversionActive {
            commitLiveConversion(client: client)
            return
        }

        var text = composer.flush()
        if shiftKatakanaActive || capsLockKatakanaActive {
            text = hiraganaToKatakana(text)
            shiftKatakanaActive = false
        }
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    private func handleBackspace(client: any IMKTextInput) -> Bool {
        guard composer.isComposing else { return false }
        let result = composer.deleteBackward()
        let display = result.composing + result.pending

        if display.isEmpty {
            // All text deleted — clean up live conversion state
            if liveConversionActive {
                mozcConverter.cancel()
                liveConversionActive = false
            }
            client.setMarkedText("" as NSString,
                                 selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: replacementRange())
        } else if liveConversionActive && !composer.composedKana.isEmpty {
            // Re-feed reduced hiragana for live conversion
            updateLiveConversion(pending: composer.pendingRomaji, client: client)
        } else {
            // No kana left (only pending romaji) or live conversion off
            if liveConversionActive {
                mozcConverter.cancel()
                liveConversionActive = false
            }
            client.setMarkedText(display as NSString,
                                 selectionRange: NSRange(location: display.count, length: 0),
                                 replacementRange: replacementRange())
        }
        return true
    }

    // MARK: - Preedit Rendering

    /// Render Mozc preedit segments as attributed marked text.
    private func renderPreedit(_ preedit: Mozc_Commands_Preedit, client: any IMKTextInput) {
        let attrString = NSMutableAttributedString()
        var cursorPosition = 0

        for (index, segment) in preedit.segment.enumerated() {
            let text = segment.value
            let isHighlight = segment.annotation == .highlight
            let underline: NSUnderlineStyle = isHighlight ? .thick : .single

            let segAttr = NSMutableAttributedString(string: text, attributes: [
                .underlineStyle: underline.rawValue,
                .markedClauseSegment: index
            ])

            if isHighlight {
                cursorPosition = attrString.length + text.count
            }

            attrString.append(segAttr)
        }

        client.setMarkedText(attrString,
                             selectionRange: NSRange(location: cursorPosition, length: 0),
                             replacementRange: replacementRange())
    }

    // MARK: - Candidate Window

    private func showCandidateWindow(client: (any IMKTextInput)? = nil) {
        NSApp.candidatePanel?.show(candidates: mozcConverter.currentCandidateStrings,
                                   selectedIndex: mozcConverter.currentFocusedIndex,
                                   client: client)
    }

    private func hideCandidateWindow() {
        NSApp.candidatePanel?.hide()
    }

    // MARK: - Key Mapping

    /// Build a Mozc KeyEvent from a macOS keyCode (used during .converting state).
    private func buildMozcKeyEvent(keyCode: UInt16, shifted: Bool) -> Mozc_Commands_KeyEvent? {
        var keyEvent = Mozc_Commands_KeyEvent()

        // Check configurable Japanese IME keys first
        if let specialKey = japaneseIMEKeyToSpecialKey(keyCode) {
            keyEvent.specialKey = specialKey
            if shifted { keyEvent.modifierKeys = [.shift] }
            return keyEvent
        }

        switch keyCode {
        case 0x7B: keyEvent.specialKey = .left
        case 0x7C: keyEvent.specialKey = .right
        case 0x7E: keyEvent.specialKey = .up
        case 0x7D: keyEvent.specialKey = .down
        case 0x31: keyEvent.specialKey = .space
        case 0x24, 0x4C: keyEvent.specialKey = .enter
        case 0x35: keyEvent.specialKey = .escape
        case 0x33: keyEvent.specialKey = .backspace
        case 0x30: keyEvent.specialKey = .tab
        default:
            return nil
        }

        if shifted {
            keyEvent.modifierKeys = [.shift]
        }

        return keyEvent
    }

    /// Map a macOS keyCode to a Mozc SpecialKey using the configurable Japanese IME key settings.
    /// Returns nil if the keyCode doesn't match any configured Japanese IME key.
    private func japaneseIMEKeyToSpecialKey(_ keyCode: UInt16) -> Mozc_Commands_KeyEvent.SpecialKey? {
        let config = Settings.shared.japaneseKeyConfig
        switch keyCode {
        case config.hiraganaKeyCode:     return .f6
        case config.fullKatakanaKeyCode: return .f7
        case config.halfKatakanaKeyCode: return .f8
        case config.fullRomajiKeyCode:   return .f9
        case config.halfRomajiKeyCode:   return .f10
        default: return nil
        }
    }

    /// Returns a Japanese symbol string for punctuation/slash/yen keys based on settings,
    /// or nil if the keyCode should not produce a special symbol.
    private func symbolForKeyCode(_ keyCode: UInt16) -> String? {
        let config = Settings.shared.japaneseKeyConfig

        switch keyCode {
        case 0x2F: // Period key
            return config.punctuationStyle == .japanese ? "\u{3002}" : "\u{FF0E}"
        case 0x2B: // Comma key
            return config.punctuationStyle == .japanese ? "\u{3001}" : "\u{FF0C}"
        case 0x2C: // Slash key
            return config.slashToNakaguro ? "\u{30FB}" : "/"
        case 0x5D: // Yen key (JIS keyboard)
            return config.yenKeyToYen ? "\u{00A5}" : "\\"
        case 0x2A: // Backslash key (US keyboard)
            return config.yenKeyToYen ? "\u{00A5}" : "\\"
        default:
            return nil
        }
    }

    private func replacementRange() -> NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }

    /// Convert hiragana string to full-width katakana.
    /// Hiragana U+3041-U+3096 -> Katakana U+30A1-U+30F6 (offset 0x60)
    private func hiraganaToKatakana(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar in
            if scalar.value >= 0x3041 && scalar.value <= 0x3096 {
                return Character(Unicode.Scalar(scalar.value + 0x60)!)
            }
            // ー is already katakana, pass through
            return Character(scalar)
        })
    }

    // MARK: - Shift+Enter Re-injection

    /// Re-post Shift+Enter as a CGEvent so the app receives a newline after commit.
    /// The re-posted event arrives when composer.isComposing is false (composing) or
    /// conversionState is .composing (converting), so it falls through naturally.
    private static func repostShiftEnter(keyCode: UInt16) {
        DispatchQueue.main.async {
            let src = CGEventSource(stateID: .hidSystemState)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
                down.flags = .maskShift
                up.flags = .maskShift
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - KeyCode -> Character mapping

    /// Maps hardware keyCode to character, independent of system keyboard layout.
    private static func charForKeyCode(_ keyCode: UInt16, shifted: Bool) -> Character? {
        switch keyCode {
        case 0x00: return "a"
        case 0x01: return "s"
        case 0x02: return "d"
        case 0x03: return "f"
        case 0x04: return "h"
        case 0x05: return "g"
        case 0x06: return "z"
        case 0x07: return "x"
        case 0x08: return "c"
        case 0x09: return "v"
        case 0x0B: return "b"
        case 0x0C: return "q"
        case 0x0D: return "w"
        case 0x0E: return "e"
        case 0x0F: return "r"
        case 0x10: return "y"
        case 0x11: return "t"
        case 0x1F: return "o"
        case 0x20: return "u"
        case 0x22: return "i"
        case 0x23: return "p"
        case 0x25: return "l"
        case 0x26: return "j"
        case 0x28: return "k"
        case 0x29: return shifted ? ":" : ";"
        case 0x2D: return "n"
        case 0x2E: return "m"
        case 0x1B: return shifted ? nil : "-"
        default: return nil
        }
    }
}
