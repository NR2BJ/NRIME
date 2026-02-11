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

    /// Whether the engine is in Mozc conversion state (for controller routing).
    var isInConversionState: Bool {
        conversionState == .converting
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
        if conversionState == .converting {
            commitConversion(client: client)
        } else {
            commitComposing(client: client)
        }
    }

    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client else { return }

        if conversionState == .converting {
            if let text = mozcConverter.submit() {
                client.insertText(text as NSString, replacementRange: replacementRange())
            }
            conversionState = .composing
            hideCandidateWindow()
        }

        mozcConverter.reset()
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
        hideCandidateWindow()
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

        // Backspace
        if keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Enter — commit composing text as hiragana
        if keyCode == 0x24 || keyCode == 0x4C {
            let wasComposing = composer.isComposing
            commitComposing(client: client)
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
            commitComposing(client: client)
            return false
        }

        // Punctuation, slash, yen — configurable Japanese symbol handling
        if let symbol = symbolForKeyCode(keyCode) {
            commitComposing(client: client)
            client.insertText(symbol as NSString, replacementRange: replacementRange())
            return true
        }

        // Alphabetic input → romaji composition
        if let char = Self.charForKeyCode(keyCode, shifted: isShifted) {
            let shiftAction = Settings.shared.japaneseKeyConfig.shiftKeyAction

            // Caps Lock romaji: insert the character directly (bypass romaji→kana)
            if isCapsLockOn && capsAction == .romaji {
                commitComposing(client: client)
                client.insertText(String(char) as NSString, replacementRange: replacementRange())
                return true
            }

            // Shift+key with romaji action: insert the character directly (bypass romaji→kana)
            if isShifted && shiftAction == .romaji {
                commitComposing(client: client)
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

        // Handle committed text
        if let committed = result.committedText {
            client.insertText(committed as NSString, replacementRange: replacementRange())
            conversionState = .composing
            composer.clear()
            hideCandidateWindow()

            // Check if Mozc started a new preedit after commit
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
            }
            return true
        }

        // Handle preedit update (segment navigation, candidate change, etc.)
        if let preedit = result.preedit {
            if preedit.segment.isEmpty {
                // Mozc cleared the preedit (e.g., Escape revert)
                conversionState = .composing
                composer.clear()
                client.setMarkedText("" as NSString,
                                     selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: replacementRange())
                hideCandidateWindow()
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

        // No preedit and no result — conversion probably ended
        if !result.consumed {
            conversionState = .composing
            composer.clear()
            hideCandidateWindow()
            return false
        }

        return true
    }

    // MARK: - Conversion Helpers

    private func triggerMozcConversion(client: any IMKTextInput) -> Bool {
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }

        if mozcConverter.convert(hiragana: hiragana) {
            conversionState = .converting

            // Render preedit segments from Mozc if available, otherwise show hiragana
            client.setMarkedText(hiragana as NSString,
                                 selectionRange: NSRange(location: hiragana.count, length: 0),
                                 replacementRange: replacementRange())

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

        guard mozcConverter.feedHiragana(hiragana) else {
            client.insertText(hiragana as NSString, replacementRange: replacementRange())
            return true
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

    private func commitConversion(client: any IMKTextInput) {
        if let text = mozcConverter.submit() {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
        conversionState = .composing
        composer.clear()
        hideCandidateWindow()
    }

    private func commitComposing(client: any IMKTextInput) {
        guard composer.isComposing else { return }
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
        NSApp.candidatePanel?.show(candidates: mozcConverter.currentCandidateStrings, client: client)
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
            return config.punctuationStyle == .japanese ? "。" : "．"
        case 0x2B: // Comma key
            return config.punctuationStyle == .japanese ? "、" : "，"
        case 0x2C: // Slash key
            return config.slashToNakaguro ? "・" : "/"
        case 0x5D: // Yen key (JIS keyboard)
            return config.yenKeyToYen ? "¥" : "\\"
        case 0x2A: // Backslash key (US keyboard)
            return config.yenKeyToYen ? "¥" : "\\"
        default:
            return nil
        }
    }

    private func replacementRange() -> NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }

    /// Convert hiragana string to full-width katakana.
    /// Hiragana U+3041-U+3096 → Katakana U+30A1-U+30F6 (offset 0x60)
    private func hiraganaToKatakana(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar in
            if scalar.value >= 0x3041 && scalar.value <= 0x3096 {
                return Character(Unicode.Scalar(scalar.value + 0x60)!)
            }
            // ー is already katakana, pass through
            return Character(scalar)
        })
    }

    // MARK: - KeyCode → Character mapping

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
        case 0x1B: return "-"
        default: return nil
        }
    }
}
