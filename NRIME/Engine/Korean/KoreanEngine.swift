import Cocoa
import InputMethodKit

final class KoreanEngine: InputEngine {
    private let automata = HangulAutomata()
    private var hanjaConverter: HanjaConverter?

    // The backspace key code
    private let backspaceKeyCode: UInt16 = 0x33

    init() {
        self.hanjaConverter = HanjaConverter()
        if hanjaConverter == nil {
            NSLog("NRIME: Warning — HanjaConverter failed to initialize (hanja.db missing?)")
        }
    }

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        guard event.type == .keyDown else { return false }

        // Ignore events with Command, Control, or Option modifiers (system shortcuts)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            commitComposing(client: client)
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
        // Commit composing text and let the system handle the key
        commitComposing(client: client)
        return false
    }

    func reset(client: any IMKTextInput) {
        commitComposing(client: client)
    }

    /// Clear automata state without committing (used when hanja candidate replaces composing text).
    func clearAutomataState() {
        _ = automata.flush()
    }

    /// Force commit any composing text (called from deactivateServer).
    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client, automata.isComposing else { return }
        let text = automata.flush()
        if !text.isEmpty {
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
        } else if result.committed.isEmpty {
            // No committed text and no composing text — clear marked text
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
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
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
        let results = converter.lookupCandidates(for: text)
        if results.isEmpty { return true }

        let candidateStrings = results.map { "\($0.hanja) \($0.meaning)" }

        if isSelectedText {
            // Convert selected text to marked text so Enter commits as IME confirmation
            // (not as app-level action like "Send" in Messages).
            let selRange = client.selectedRange()
            client.setMarkedText(text as NSString,
                                 selectionRange: NSRange(location: text.count, length: 0),
                                 replacementRange: selRange)
        }

        if let panel = (NSApp.delegate as? AppDelegate)?.candidatePanel {
            panel.show(candidates: candidateStrings, client: client)
        }

        return true
    }

    private func replacementRange() -> NSRange {
        return NSRange(location: NSNotFound, length: NSNotFound)
    }

}
