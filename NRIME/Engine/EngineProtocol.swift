import Cocoa
import InputMethodKit

protocol InputEngine: AnyObject {
    /// Handle a key event. Returns true if the event was consumed.
    func handleEvent(_ event: NSEvent, client: any IMKTextInput) -> Bool

    /// Force-commit any composing text and reset state.
    func reset(client: any IMKTextInput)
}
