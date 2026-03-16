import Cocoa
import InputMethodKit

final class KoreanEngine: InputEngine {
    private let automata = HangulAutomata()
    private var hanjaConverter: HanjaConverter?
    private let hanjaSelectionStore = HanjaSelectionStore()
    private var hanjaSource: HanjaSource = .none

    // The backspace key code
    private let backspaceKeyCode: UInt16 = 0x33

    private enum HanjaSource {
        case none
        case composing(String)
        case selectedText(String)

        var text: String? {
            switch self {
            case .none:
                return nil
            case .composing(let text), .selectedText(let text):
                return text
            }
        }
    }

    init() {
        self.hanjaConverter = HanjaConverter()
        if hanjaConverter == nil {
            NSLog("NRIME: Warning — HanjaConverter failed to initialize (hanja.db missing?)")
        }
    }

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        guard event.type == .keyDown else { return false }

        // Modifier keys (Cmd, Ctrl, Option) while composing:
        // Cmd+key goes through performKeyEquivalent (not keyDown), so return false
        // won't forward it. Commit text, then repost the event via CGEvent with a tag
        // so our controller detects it and passes it through to the host app.
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            if automata.isComposing {
                commitAndRepostEvent(event: event, client: client)
                return true
            }
            return false
        }

        // Handle backspace
        if event.keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Primary: keyCode-based jamo lookup (works in ALL apps including Electron/VSCode)
        let isShifted = event.modifierFlags.contains(.shift)
        if let jamo = JamoTable.jamo(forKeyCode: event.keyCode, shifted: isShifted) {
            let result = automata.input(jamo)
            applyResult(result, client: client)
            return true
        }

        // Non-jamo key (space, enter, punctuation, numbers, etc.)

        // Shift+Enter while composing: commit text, then insert newline after delay.
        // Cannot use "commit + return false" — Shift+Return has no StandardKeyBinding.dict
        // entry, so Chromium's oldHasMarkedText check misinterprets the forwarded event.
        // Cannot use synchronous insertText("\n") — gets batched/swallowed by Chromium.
        // Async insertText("\n") via IME client API avoids the interpretKeyEvents: path entirely.
        if automata.isComposing && isShifted && Self.isEnterKey(event.keyCode) {
            commitComposing(client: client)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [self] in
                client.insertText("\n" as NSString, replacementRange: replacementRange())
            }
            return true
        }

        // All other non-jamo keys: commit and let the system handle the key.
        commitComposing(client: client)
        return false
    }

    func reset(client: any IMKTextInput) {
        commitComposing(client: client)
    }

    /// Whether the automata is currently composing a character.
    var isCurrentlyComposing: Bool { automata.isComposing }

    /// Clear automata state without committing (used when hanja candidate replaces composing text).
    func clearAutomataState() {
        _ = automata.flush()
        clearHanjaSession()
    }

    /// Restore the original text that was used to open the hanja candidate panel.
    /// This is used when dismissing preview-only UI states (escape, leaving grid mode).
    func restoreHanjaSource(client: any IMKTextInput) {
        guard let text = hanjaSource.text, !text.isEmpty else { return }
        client.setMarkedText(
            text as NSString,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: replacementRange()
        )
    }

    /// Clears only the temporary hanja conversion session state.
    func clearHanjaSession() {
        hanjaSource = .none
    }

    func rememberSelectedHanja(_ hanja: String) {
        guard let sourceText = hanjaSource.text else { return }
        hanjaSelectionStore.remember(hanja: hanja, for: sourceText)
    }

    /// Force commit any composing text (called from deactivateServer).
    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client, automata.isComposing else { return }
        let text = automata.flush()
        clearHanjaSession()
        if !text.isEmpty {
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: replacementRange()
            )
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    // MARK: - Private

    private func handleBackspace(client: any IMKTextInput) -> Bool {
        guard automata.isComposing else {
            return false // Let the system handle backspace (delete previous char)
        }

        let result = automata.deleteBackward()

        if result.composing.isEmpty {
            // All jamo deleted — clear marked text
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: replacementRange()
            )
        } else {
            // Update marked text with remaining composition
            client.setMarkedText(
                result.composing as NSString,
                selectionRange: NSRange(location: result.composing.count, length: 0),
                replacementRange: replacementRange()
            )
        }

        return true
    }

    private func applyResult(_ result: HangulResult, client: any IMKTextInput) {
        // Commit any finalized text
        if !result.committed.isEmpty {
            client.insertText(result.committed as NSString, replacementRange: replacementRange())
        }

        // Update composing text (marked text)
        if !result.composing.isEmpty {
            client.setMarkedText(
                result.composing as NSString,
                selectionRange: NSRange(location: result.composing.count, length: 0),
                replacementRange: replacementRange()
            )
        } else {
            // Committed text but no composing text, or no text at all — clear marked text
            client.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: replacementRange()
            )
        }
    }

    private func commitComposing(client: any IMKTextInput) {
        guard automata.isComposing else { return }
        let text = automata.flush()
        clearHanjaSession()
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }


    /// Commit composing text and repost the modifier key event via CGEvent.
    /// Cmd+key events go through performKeyEquivalent (not keyDown), so return false
    /// won't forward them. Instead, we commit text synchronously and repost the event
    /// as a tagged CGEvent so the controller detects the tag and passes it through.
    private func commitAndRepostEvent(event: NSEvent, client: any IMKTextInput) {
        commitComposing(client: client)

        // Repost the key event via CGEvent with our repost tag.
        // The controller's handle() checks eventSourceUserData and returns false
        // for tagged events, allowing them to pass through to the host app.
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        DispatchQueue.main.async {
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
            keyDown.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
            keyDown.setIntegerValueField(.eventSourceUserData, value: KeyEventReposter.repostTag)
            keyDown.post(tap: .cghidEventTap)

            // Key up after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
                keyUp.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
                keyUp.setIntegerValueField(.eventSourceUserData, value: KeyEventReposter.repostTag)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// Whether the given keyCode is an Enter key (Return or numpad Enter).
    private static func isEnterKey(_ keyCode: UInt16) -> Bool {
        keyCode == 0x24 || keyCode == 0x4C  // Return, numpad Enter
    }

    func triggerHanjaConversion(client: any IMKTextInput) -> Bool {
        guard let converter = hanjaConverter else { return true }

        // 1. Try composing text first (actively being typed)
        let composing = automata.currentComposingText()
        if !composing.isEmpty {
            return showHanjaCandidates(for: composing, converter: converter, client: client, isSelectedText: false)
        }

        // 2. Fall back to selected text (user dragged to select)
        let selRange = client.selectedRange()
        if selRange.location != NSNotFound && selRange.length > 0 {
            if let selAttr = client.attributedSubstring(from: selRange),
               !selAttr.string.isEmpty {
                return showHanjaCandidates(for: selAttr.string, converter: converter, client: client, isSelectedText: true)
            }
        }

        return true
    }

    private func showHanjaCandidates(for text: String, converter: HanjaConverter, client: any IMKTextInput, isSelectedText: Bool) -> Bool {
        let results = hanjaSelectionStore.prioritize(
            converter.lookupCandidates(for: text),
            for: text
        )
        if results.isEmpty {
            clearHanjaSession()
            return true
        }

        let candidateStrings = results.map { "\($0.hanja) \($0.meaning)" }
        hanjaSource = isSelectedText ? .selectedText(text) : .composing(text)

        if isSelectedText {
            // Convert selected text to marked text so Enter commits as IME confirmation
            // (not as app-level action like "Send" in Messages).
            let selRange = client.selectedRange()
            client.setMarkedText(text as NSString,
                                 selectionRange: NSRange(location: text.count, length: 0),
                                 replacementRange: selRange)
        }

        NSApp.candidatePanel?.show(candidates: candidateStrings, client: client)

        return true
    }

    private func replacementRange() -> NSRange {
        return NSRange(location: NSNotFound, length: NSNotFound)
    }

}
