import Cocoa
import InputMethodKit

final class KoreanEngine: InputEngine {
    private let automata = HangulAutomata()
    var hanjaConverter: HanjaConverter?

    // The backspace key code
    private let backspaceKeyCode: UInt16 = 0x33

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        guard event.type == .keyDown else { return false }

        // Check for Hanja shortcut (Option + Enter)
        if event.modifierFlags.contains(.option) && event.keyCode == 0x24 {
            return triggerHanjaConversion(client: client)
        }

        // Ignore events with Command or Control modifiers (system shortcuts)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            commitComposing(client: client)
            return false
        }

        // Handle backspace
        if event.keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Get the character from the event
        guard let chars = event.characters, let char = chars.first else {
            return false
        }

        // Look up jamo
        if let jamo = JamoTable.jamo(for: char) {
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

    private func triggerHanjaConversion(client: any IMKTextInput) -> Bool {
        guard let converter = hanjaConverter else { return false }

        let composing = automata.currentComposingText()
        guard !composing.isEmpty else { return false }

        let candidates = converter.lookupCandidates(for: composing)
        guard !candidates.isEmpty else { return false }

        converter.currentCandidateStrings = candidates.map { "\($0.hanja) \($0.meaning)" }
        converter.client = client

        // Show the candidates window
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.candidatesWindow.update()
            appDelegate.candidatesWindow.show()
        }

        return true
    }

    private func replacementRange() -> NSRange {
        return NSRange(location: NSNotFound, length: NSNotFound)
    }
}
