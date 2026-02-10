import Cocoa
import InputMethodKit

final class JapaneseEngine: InputEngine {
    private let composer = RomajiComposer()
    let mozcConverter = MozcConverter()
    private let backspaceKeyCode: UInt16 = 0x33

    /// Called when Mozc candidates are about to be shown, so controller can reset selection index.
    var onCandidatesShow: (() -> Void)?

    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        guard event.type == .keyDown else { return false }

        // Ignore events with Command, Control, or Option modifiers
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            commitComposing(client: client)
            return false
        }

        let keyCode = event.keyCode

        // Backspace
        if keyCode == backspaceKeyCode {
            return handleBackspace(client: client)
        }

        // Enter — commit composing text
        if keyCode == 0x24 || keyCode == 0x4C {
            commitComposing(client: client)
            return composer.isComposing // was composing → consume; otherwise pass through
        }

        // Space — trigger Mozc conversion (or commit hiragana if Mozc unavailable)
        if keyCode == 0x31 {
            if composer.isComposing {
                return triggerMozcConversion(client: client)
            }
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

        // Arrow keys, Tab, etc. — commit and pass through
        if keyCode == 0x7E || keyCode == 0x7D || keyCode == 0x7B || keyCode == 0x7C || keyCode == 0x30 {
            commitComposing(client: client)
            return false
        }

        // Alphabetic input → romaji composition
        // Use keyCode-based character lookup for reliability (like KoreanEngine)
        let isShifted = event.modifierFlags.contains(.shift)
        if let char = Self.charForKeyCode(keyCode, shifted: isShifted) {
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

    func reset(client: any IMKTextInput) {
        commitComposing(client: client)
    }

    func forceCommit(client: (any IMKTextInput)?) {
        guard let client = client else { return }
        mozcConverter.reset()
        guard composer.isComposing else { return }
        let text = composer.flush()
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    /// Clear composer state without committing (used after candidate selection).
    func clearComposerState() {
        composer.clear()
    }

    // MARK: - Private

    private func triggerMozcConversion(client: any IMKTextInput) -> Bool {
        let hiragana = composer.flush()
        guard !hiragana.isEmpty else { return false }

        if mozcConverter.convert(hiragana: hiragana) {
            // Keep hiragana as marked text while showing candidates
            client.setMarkedText(hiragana as NSString,
                                 selectionRange: NSRange(location: hiragana.count, length: 0),
                                 replacementRange: replacementRange())

            onCandidatesShow?()
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.candidatesWindow.update()
                appDelegate.candidatesWindow.show(kIMKLocateCandidatesBelowHint)
            }
            return true
        }

        // Mozc unavailable or no candidates — commit hiragana directly
        client.insertText(hiragana as NSString, replacementRange: replacementRange())
        return true
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

    private func commitComposing(client: any IMKTextInput) {
        guard composer.isComposing else { return }
        let text = composer.flush()
        if !text.isEmpty {
            client.insertText(text as NSString, replacementRange: replacementRange())
        }
    }

    private func replacementRange() -> NSRange {
        NSRange(location: NSNotFound, length: NSNotFound)
    }

    // MARK: - KeyCode → Character mapping

    /// Maps hardware keyCode to character, independent of system keyboard layout.
    /// Uses US QWERTY layout mapping (same approach as KoreanEngine/JamoTable).
    private static func charForKeyCode(_ keyCode: UInt16, shifted: Bool) -> Character? {
        // Only map alphabetic keys and hyphen/minus for ー
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
        case 0x29: return shifted ? ":" : ";"  // pass through for now
        case 0x2C: return "/"  // pass through
        case 0x2D: return "n"
        case 0x2E: return "m"
        case 0x1B: return "-"  // minus → ー (long vowel mark)
        default: return nil
        }
    }
}
