import Cocoa
import InputMethodKit

final class EnglishEngine: InputEngine {
    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool {
        // Pure passthrough — let the system handle the keystroke
        return false
    }

    func reset(client: any IMKTextInput) {
        // No state to reset
    }
}
