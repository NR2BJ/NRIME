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

    /// Tracks whether Caps Lock katakana mode is active (for commitComposing to use).
    private var capsLockKatakanaActive = false

    /// Whether the engine is in Mozc conversion state (for controller routing).
    var isInConversionState: Bool {
        conversionState == .converting
    }

    var isCurrentlyComposing: Bool { composer.isComposing }

#if DEBUG
    /// Test seam: enter the converting state around whatever the converter holds.
    func markConvertingForTesting() {
        conversionState = .converting
    }
#endif

    // MARK: - InputEngine

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        // Handle Caps Lock (flagsChanged) for Japanese-specific behavior
        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: client)
        }

        guard event.type == .keyDown else { return false }

        // Modifier keys (Cmd, Ctrl, Option) while active:
        // Commit text, then repost via CGEvent so the app receives the shortcut.
        let mods = event.modifierFlags
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            let wasActive = conversionState == .converting || composer.isComposing
            if conversionState == .converting {
                commitConversion(client: client)
            } else if composer.isComposing {
                commitComposing(client: client)
            }
            if wasActive {
                // A repost that cannot be delivered would swallow the shortcut.
                guard KeyEventReposter.canPostEvents else { return false }
                KeyEventReposter.repost(event, after: Settings.shared.shiftEnterDelay)
                return true
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
        if conversionState == .converting {
            commitConversion(client: client)
        } else {
            commitComposing(client: client)
        }
    }

    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client else { return }

        if conversionState == .converting {
            // Commit what is on screen now and tell Mozc afterwards. This runs
            // inside a mode switch or a focus change, and a synchronous submit
            // to a slow or restarting Mozc used to hold it — and every key
            // behind it — for up to 1.5 s.
            if let text = mozcConverter.commitLater() {
                // Commit via insertText only — setMarkedText("") first deletes the
                // inserted text in Chromium (oldHasMarkedText) and JS-managed editors.
                client.insertText(text as NSString, replacementRange: replacementRange())
            }
            conversionState = .composing
            hideCandidateWindow()
        } else {
            mozcConverter.reset()
        }

        guard composer.isComposing else {
            clearDisplayModeState()
            return
        }
        // Resolve what the user is actually looking at before clearing the
        // flag that decides it — katakana mode changes the committed string,
        // and clearing it first commits raw hiragana instead.
        let text = takeComposingCommitText()
        if !text.isEmpty {
            // Commit via insertText only — setMarkedText("") first deletes the
            // inserted text in Chromium (oldHasMarkedText) and JS-managed editors.
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    /// Drop the display-mode flags without committing anything.
    private func clearDisplayModeState() {
        capsLockKatakanaActive = false
    }

    /// The string to commit for the current composing buffer, matching what is
    /// displayed, consuming the display-mode state it depends on.
    private func takeComposingCommitText() -> String {
        var text = composer.flush()
        if capsLockKatakanaActive {
            text = hiraganaToKatakana(text)
        }
        clearDisplayModeState()
        return text
    }

    /// Clear all engine state without inserting text.
    /// Used when the previous client is gone (e.g., activateServer after Electron focus change).
    func clearState() {
        conversionState = .composing
        mozcConverter.reset()
        mozcConverter.currentCandidateStrings = []
        capsLockKatakanaActive = false
        composer.clear()
        hideCandidateWindow()
    }

    /// Exit conversion state (used by controller after candidate selection).
    func exitConversionState() {
        conversionState = .composing
        // Full reset (not just the display list) — after a failed submit the
        // converter would otherwise keep stale preedit/candidates/originalHiragana
        // describing a conversion that no longer exists.
        mozcConverter.reset()
        mozcConverter.currentCandidateStrings = []
        composer.clear()
        capsLockKatakanaActive = false
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
            hideCandidateWindow()

            // Check if Mozc started a new preedit after commit (next segment)
            if let preedit = result.preedit, !preedit.segment.isEmpty {
                renderPreedit(preedit, client: client)
                conversionState = .converting
                if result.hasCandidates {
                    showCandidateWindow(client: client)
                }
            }
            // Otherwise insertText above already ended the composition — do not
            // call setMarkedText("") here (oldHasMarkedText trigger in Chromium).
            return true
        }

        // Handle preedit update (segment navigation, candidate change)
        if let preedit = result.preedit {
            if preedit.segment.isEmpty {
                // Mozc cleared the preedit (e.g. user deleted all segments via Backspace).
                // Don't restore original hiragana — the user intentionally deleted everything.
                revertToComposing(client: client, restore: false)
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
        // Don't restore original hiragana — Mozc decided to clear everything.
        revertToComposing(client: client, restore: false)
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
        let config = Settings.shared.japaneseKeyConfig

        // Backspace
        if keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Enter — commit composing text.
        if keyCode == 0x24 || keyCode == 0x4C {
            let wasComposing = composer.isComposing

            // Shift+Enter while composing: commit text and insert newline.
            // Chromium: async newline (insertText("\n"), or a replayed key press
            // for apps that submit on programmatic "\n" — Codex).
            // All other apps: commit + return false — system handles the original Enter.
            if wasComposing && isShifted {
                commitComposing(client: client)
                if ChromiumDetector.isFrontmostAppChromium {
                    KeyEventReposter.performChromiumNewline(keyCode: event.keyCode,
                                                            client: client,
                                                            delay: Settings.shared.shiftEnterDelay)
                    return true
                }
                return false
            }

            commitComposing(client: client)
            return wasComposing
        }

        // Space — trigger Mozc conversion, or commit + space, or insert full-width space
        if keyCode == 0x31 {
            if composer.isComposing {
                // Katakana mode: commit directly, no Mozc conversion
                if capsLockKatakanaActive {
                    commitComposing(client: client)
                    let space = config.fullWidthSpace ? "\u{3000}" : " "
                    client.insertText(space as NSString, replacementRange: replacementRange())
                    return true
                }
                if config.conversionTriggerSpace {
                    return triggerMozcConversion(client: client)
                }
                // Trigger disabled: commit composing text, then insert space
                commitComposing(client: client)
                let space = config.fullWidthSpace ? "\u{3000}" : " "
                client.insertText(space as NSString, replacementRange: replacementRange())
                return true
            }
            // Not composing: insert full-width space if configured
            if config.fullWidthSpace {
                client.insertText("\u{3000}" as NSString, replacementRange: replacementRange())
                return true
            }
            return false
        }

        // Tab while composing — trigger conversion if enabled, otherwise pass through
        if keyCode == 0x30 && composer.isComposing {
            if capsLockKatakanaActive {
                commitComposing(client: client)
                return true
            }
            if config.conversionTriggerTab {
                return triggerMozcConversion(client: client)
            }
            commitComposing(client: client)
            return false
        }

        // Escape — cancel composing
        if keyCode == 0x35 {
            if composer.isComposing {
                composer.clear()
                client.setMarkedText("" as NSString,
                                     selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: replacementRange())
                return true
            }
            return false
        }

        // Arrow keys — commit and pass through
        if keyCode == 0x7E || keyCode == 0x7D || keyCode == 0x7B || keyCode == 0x7C {
            commitComposing(client: client)
            return false
        }

        // Symbol keys (punctuation, brackets, shifted symbols like ! ?) —
        // commit composing text, then insert the symbol styled per settings.
        // Width comes from punctuationStyle alone; the Caps Lock romaji action
        // governs letters and must not reach symbols, otherwise ! and ? ignore
        // the punctuation setting entirely.
        if let symbol = symbolForKeyCode(keyCode, shifted: isShifted) {
            commitComposing(client: client)
            client.insertText(symbol as NSString, replacementRange: replacementRange())
            return true
        }

        // Alphabetic input -> romaji composition. Shift has no special meaning:
        // Shift+letter composes the same kana (romaji is typed in English mode).
        if let char = Self.charForKeyCode(keyCode, shifted: isShifted) {
            // Caps Lock romaji: insert the character directly (bypass romaji->kana)
            if isCapsLockOn && config.capsLockAction == .romaji {
                commitComposing(client: client)
                client.insertText(String(char) as NSString, replacementRange: replacementRange())
                return true
            }

            // Caps Lock katakana: direct output without composition
            if isCapsLockOn && config.capsLockAction == .katakana {
                let result = composer.input(char)
                let kana = composer.composedKana
                if !kana.isEmpty {
                    let katakana = kana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? kana
                    composer.clearComposed()
                    client.insertText(katakana as NSString, replacementRange: replacementRange())
                }
                if !result.pending.isEmpty {
                    client.setMarkedText(result.pending as NSString,
                                         selectionRange: NSRange(location: result.pending.count, length: 0),
                                         replacementRange: replacementRange())
                }
                capsLockKatakanaActive = true
                return true
            }
            capsLockKatakanaActive = false

            let result = composer.input(char)
            let display = result.composing + result.pending
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
        commitComposing(client: client)
        return false
    }

    // MARK: - Converting State (Mozc key forwarding)

    private func handleConvertingEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        let keyCode = event.keyCode
        let isShifted = event.modifierFlags.contains(.shift)

        // Shift+Enter — commit conversion and insert newline.
        // Chromium: async newline (insertText("\n"), or a replayed key press
        // for apps that submit on programmatic "\n" — Codex).
        // Others: commit + return false.
        if (keyCode == 0x24 || keyCode == 0x4C) && isShifted {
            commitConversion(client: client)
            if ChromiumDetector.isFrontmostAppChromium {
                KeyEventReposter.performChromiumNewline(keyCode: keyCode,
                                                        client: client,
                                                        delay: Settings.shared.shiftEnterDelay)
                return true
            }
            return false
        }

        // Escape — revert to hiragana composing state (not Mozc converting).
        // This returns to .composing with the original hiragana in the composer,
        // so Backspace works naturally (one char at a time, no ghost text).
        if keyCode == 0x35 {
            revertToComposing(client: client)
            return true
        }

        // Symbol keys — commit the conversion, then insert the styled symbol.
        if let symbol = symbolForKeyCode(keyCode, shifted: isShifted) {
            commitConversion(client: client)
            client.insertText(symbol as NSString, replacementRange: replacementRange())
            return true
        }

        // A letter starts the next word: commit this conversion and re-enter
        // composing with the same key (standard IME behavior). Without this the
        // letter would fall through to "commit + pass through" and leak into
        // the document as raw ASCII ("日本語k" instead of 日本語 + composing か).
        if Self.charForKeyCode(keyCode, shifted: isShifted) != nil {
            commitConversion(client: client)
            return handleComposingEvent(event, client: client)
        }

        // Build Mozc KeyEvent from NSEvent
        guard let mozcKey = buildMozcKeyEvent(keyCode: keyCode, shifted: isShifted) else {
            // Unknown key — commit conversion and pass through
            commitConversion(client: client)
            return false
        }

        // Send to Mozc. An Output carrying an error code is a failed request,
        // not an empty conversion — processing it as a normal answer silently
        // ends the composition the user is still editing.
        guard let output = mozcConverter.sendKeyEvent(mozcKey) else {
            // No answer: Mozc is hung or gone, and asking it to submit would
            // only wait again. Commit what is on screen and let it restart.
            if let text = mozcConverter.displayedText {
                client.insertText(text as NSString, replacementRange: replacementRange())
            }
            mozcConverter.discardLocalState()
            mozcConverter.serverStoppedAnswering()
            leaveConversion()
            return false
        }
        guard !output.hasErrorCode else {
            commitConversion(client: client)
            return false
        }

        // Process Mozc's response
        let result = mozcConverter.updateFromOutput(output)
        return processMozcResult(result, client: client)
    }

    // MARK: - Conversion Helpers

    private func triggerMozcConversion(client: any IMKTextInput) -> Bool {
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }
        DeveloperLogger.shared.log("Japanese", "Conversion triggered",
                                   metadata: ["length": "\(hiragana.count)"])

        if mozcConverter.convert(hiragana: hiragana) {
            DeveloperLogger.shared.log("Japanese", "Conversion succeeded",
                                       metadata: ["candidates": "\(mozcConverter.currentCandidateStrings.count)"])
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

        keepComposing(hiragana, client: client)
        return true
    }

    /// Mozc could not convert — it is starting or restarting in the background,
    /// and nothing waits for it here. Keep what was typed as the composition
    /// rather than committing it, so Space converts once Mozc is back and Enter
    /// still commits it as is.
    private func keepComposing(_ hiragana: String, client: any IMKTextInput) {
        mozcConverter.discardLocalState()
        composer.restore(kana: hiragana)
        client.setMarkedText(hiragana as NSString,
                             selectionRange: NSRange(location: hiragana.count, length: 0),
                             replacementRange: replacementRange())
    }

    /// Send a function key to Mozc for the current composition: F7 (katakana)
    /// or F10 (romaji) — the Caps Lock actions.
    private func sendFunctionKeyToMozc(_ specialKey: Mozc_Commands_KeyEvent.SpecialKey,
                                       client: any IMKTextInput) -> Bool {
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }
        mozcConverter.prepareForConversion(hiragana: hiragana)

        guard mozcConverter.feedHiragana(hiragana) else {
            keepComposing(hiragana, client: client)
            return true
        }

        var keyEvent = Mozc_Commands_KeyEvent()
        keyEvent.specialKey = specialKey

        guard let output = mozcConverter.sendKeyEvent(keyEvent) else {
            keepComposing(hiragana, client: client)
            return true
        }

        let result = mozcConverter.updateFromOutput(output)

        if let committed = result.committedText {
            mozcConverter.reset()
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
            // The key produced no preedit — commit hiragana as fallback
            mozcConverter.reset()
            client.insertText(hiragana as NSString, replacementRange: replacementRange())
        }

        return true
    }

    /// Revert from converting state back to composing.
    /// - Parameter restore: If true (default), restores original hiragana into the composer
    ///   so the user can continue editing. Used by Escape. If false, clears everything
    ///   (used when Mozc itself cleared the preedit, e.g. user deleted all segments via Backspace).
    private func revertToComposing(client: any IMKTextInput, restore: Bool = true) {
        let hiragana = restore ? mozcConverter.originalHiragana : ""
        mozcConverter.cancel()
        mozcConverter.reset()
        conversionState = .composing
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
        if let text = mozcConverter.commit() {
            // Commit via insertText only — setMarkedText("") first deletes the
            // inserted text in Chromium (oldHasMarkedText) and JS-managed editors.
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
        leaveConversion()
    }

    /// Back to composing once the conversion has been committed.
    private func leaveConversion() {
        conversionState = .composing
        composer.clear()
        capsLockKatakanaActive = false
        hideCandidateWindow()
    }

    private func commitComposing(client: any IMKTextInput) {
        guard composer.isComposing else { return }

        var text = composer.flush()
        if capsLockKatakanaActive {
            text = hiraganaToKatakana(text)
            capsLockKatakanaActive = false
        }
        if !text.isEmpty {
            // Commit via insertText only — setMarkedText("") first deletes the
            // inserted text in Chromium (oldHasMarkedText) and JS-managed editors.
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    private func handleBackspace(client: any IMKTextInput) -> Bool {
        guard composer.isComposing else { return false }
        let result = composer.deleteBackward()
        let display = result.composing + result.pending
        client.setMarkedText(display as NSString,
                             selectionRange: NSRange(location: display.count, length: 0),
                             replacementRange: replacementRange())
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
                // NSRange positions are UTF-16 units; String.count is grapheme
                // clusters and diverges on non-BMP kanji (e.g. 𠮟る).
                cursorPosition = attrString.length + (text as NSString).length
            }

            attrString.append(segAttr)
        }

        client.setMarkedText(attrString,
                             selectionRange: NSRange(location: cursorPosition, length: 0),
                             replacementRange: replacementRange())
    }

    // MARK: - Candidate Window

    private func showCandidateWindow(client: (any IMKTextInput)? = nil) {
        let candidates = candidateDisplayStrings
        guard !candidates.isEmpty else {
            NSApp.candidatePanel?.hide()
            return
        }
        NSApp.candidatePanel?.show(candidates: candidates,
                                   selectedIndex: mozcConverter.currentFocusedIndex,
                                   client: client)
    }

    private func hideCandidateWindow() {
        NSApp.candidatePanel?.hide()
    }

    var candidateDisplayStrings: [String] {
        if !mozcConverter.currentCandidateStrings.isEmpty {
            return mozcConverter.currentCandidateStrings
        }
        if let preedit = mozcConverter.currentPreedit, !preedit.segment.isEmpty {
            return [preedit.segment.map(\.value).joined()]
        }
        return []
    }

    // MARK: - Key Mapping

    /// Build a Mozc KeyEvent from a macOS keyCode (used during .converting state).
    private func buildMozcKeyEvent(keyCode: UInt16, shifted: Bool) -> Mozc_Commands_KeyEvent? {
        var keyEvent = Mozc_Commands_KeyEvent()

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

    /// Returns a Japanese symbol string for symbol/punctuation keys based on settings,
    /// or nil if the keyCode should not produce a special symbol.
    private func symbolForKeyCode(_ keyCode: UInt16, shifted: Bool) -> String? {
        Self.styledSymbol(keyCode: keyCode, shifted: shifted,
                          config: Settings.shared.japaneseKeyConfig)
    }

    /// Full symbol map for the US-ANSI layout, styled by the punctuation setting:
    /// .japanese uses Japanese conventions (。、「」〜), .fullWidthWestern uses
    /// full-width Western forms (．，［］～), .halfWidthWestern stays ASCII.
    /// keyCode-based (not event.characters) for Electron compatibility.
    ///
    /// Returns nil when the styled form equals the ASCII the keyboard already
    /// produces. The caller then passes the key through instead of consuming it
    /// and re-inserting the same character — insertText is dropped by fields that
    /// ignore IME insertion (password prompts), which would swallow the keystroke.
    static func styledSymbol(keyCode: UInt16, shifted: Bool,
                             config: JapaneseKeyConfig) -> String? {
        guard let forms = symbolForms(keyCode: keyCode, shifted: shifted, config: config) else {
            return nil
        }
        return forms.styled == forms.ascii ? nil : forms.styled
    }

    /// The styled form and the plain ASCII form for a symbol key, or nil if the
    /// key is not a symbol key.
    private static func symbolForms(
        keyCode: UInt16, shifted: Bool, config: JapaneseKeyConfig
    ) -> (styled: String, ascii: String)? {
        let style = config.punctuationStyle
        let isHalfWidth = style == .halfWidthWestern

        // Keys with dedicated settings or style-specific (non-width) forms
        switch (keyCode, shifted) {
        case (0x2F, false): // Period key
            switch style {
            case .japanese:         return ("\u{3002}", ".")  // 。
            case .fullWidthWestern: return ("\u{FF0E}", ".")  // ．
            case .halfWidthWestern: return (".", ".")
            }
        case (0x2B, false): // Comma key
            switch style {
            case .japanese:         return ("\u{3001}", ",")  // 、
            case .fullWidthWestern: return ("\u{FF0C}", ",")  // ，
            case .halfWidthWestern: return (",", ",")
            }
        case (0x2C, false): // Slash key
            if config.slashToNakaguro { return ("\u{30FB}", "/") }        // ・
            return (isHalfWidth ? "/" : "\u{FF0F}", "/")                  // ／
        case (0x2A, false), (0x5D, false): // Backslash (US) / Yen key (JIS)
            if config.yenKeyToYen { return ("\u{00A5}", "\\") }           // ¥
            return (isHalfWidth ? "\\" : "\u{FF3C}", "\\")                // ＼
        case (0x21, false): // [
            switch style {
            case .japanese:         return ("\u{300C}", "[")  // 「
            case .fullWidthWestern: return ("\u{FF3B}", "[")  // ［
            case .halfWidthWestern: return ("[", "[")
            }
        case (0x1E, false): // ]
            switch style {
            case .japanese:         return ("\u{300D}", "]")  // 」
            case .fullWidthWestern: return ("\u{FF3D}", "]")  // ］
            case .halfWidthWestern: return ("]", "]")
            }
        case (0x32, true): // ~
            switch style {
            case .japanese:         return ("\u{301C}", "~")  // 〜 (wave dash)
            case .fullWidthWestern: return ("\u{FF5E}", "~")  // ～
            case .halfWidthWestern: return ("~", "~")
            }
        default:
            break
        }

        // Symbols whose full-width form is shared by .japanese and .fullWidthWestern
        let pair: (full: String, half: String)?
        switch (keyCode, shifted) {
        case (0x12, true): pair = ("\u{FF01}", "!")  // ！
        case (0x13, true): pair = ("\u{FF20}", "@")  // ＠
        case (0x14, true): pair = ("\u{FF03}", "#")  // ＃
        case (0x15, true): pair = ("\u{FF04}", "$")  // ＄
        case (0x17, true): pair = ("\u{FF05}", "%")  // ％
        case (0x16, true): pair = ("\u{FF3E}", "^")  // ＾
        case (0x1A, true): pair = ("\u{FF06}", "&")  // ＆
        case (0x1C, true): pair = ("\u{FF0A}", "*")  // ＊
        case (0x19, true): pair = ("\u{FF08}", "(")  // （
        case (0x1D, true): pair = ("\u{FF09}", ")")  // ）
        case (0x1B, true): pair = ("\u{FF3F}", "_")  // ＿ (unshifted "-" stays ー via composer)
        case (0x18, false): pair = ("\u{FF1D}", "=") // ＝
        case (0x18, true): pair = ("\u{FF0B}", "+")  // ＋
        case (0x21, true): pair = ("\u{FF5B}", "{")  // ｛
        case (0x1E, true): pair = ("\u{FF5D}", "}")  // ｝
        case (0x2A, true), (0x5D, true): pair = ("\u{FF5C}", "|") // ｜
        case (0x29, false): pair = ("\u{FF1B}", ";") // ；
        case (0x29, true): pair = ("\u{FF1A}", ":")  // ：
        case (0x27, false): pair = ("\u{FF07}", "'") // ＇
        case (0x27, true): pair = ("\u{FF02}", "\"") // ＂
        case (0x2B, true): pair = ("\u{FF1C}", "<")  // ＜
        case (0x2F, true): pair = ("\u{FF1E}", ">")  // ＞
        case (0x2C, true): pair = ("\u{FF1F}", "?")  // ？
        case (0x32, false): pair = ("\u{FF40}", "`") // ｀
        default: pair = nil
        }

        guard let pair else { return nil }
        return (isHalfWidth ? pair.half : pair.full, pair.half)
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
        case 0x2D: return "n"
        case 0x2E: return "m"
        case 0x1B: return shifted ? nil : "-"
        default: return nil
        }
    }
}
