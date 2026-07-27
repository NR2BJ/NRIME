import Cocoa
import InputMethodKit

/// Re-posting key events to the frontmost application after committing
/// composing text.
///
/// Problem: When an IMKit input method calls `client.insertText()` inside `handle()`
/// and returns `false`, the original key event is not reliably forwarded to the host app
/// (especially in Electron-based apps like Slack, Discord, VS Code, Claude for Desktop).
///
/// Solution: Engines commit text, then repost the key event as a tagged CGEvent.
/// The controller detects the tag in `handle()` and returns `false` immediately,
/// allowing the event to pass through to the host app untouched.
///
/// For Shift+Enter, most Chromium apps get an async `insertText("\n")` instead
/// (Shift+Return has no StandardKeyBinding.dict entry, so AppKit-driven paths
/// misinterpret a replayed key). Apps whose editor submits on a programmatic
/// "\n" (ChatGPT/Codex) get the replayed key press after the commit settles —
/// with composition over, the renderer's own keydown handler inserts the line
/// break exactly as for a physical Shift+Enter.
enum KeyEventReposter {

    /// Sentinel value stored in `eventSourceUserData` to mark re-posted events.
    /// Used by controller to detect and pass through reposted events.
    /// Value is "NRIME" encoded as ASCII hex bytes.
    static let repostTag: Int64 = 0x4E52494D45

#if DEBUG
    /// Test seam: captures reposts instead of injecting real system events.
    static var captureForTesting: ((_ keyCode: UInt16, _ flags: CGEventFlags) -> Void)?
#endif

    /// Post a tagged key press (down+up) after a delay. The controller sees the
    /// tag and passes the event straight through to the host app.
    static func postKeyPress(keyCode: UInt16, flags: CGEventFlags, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
#if DEBUG
            if let capture = captureForTesting {
                capture(keyCode, flags)
                return
            }
#endif
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
            keyDown.flags = flags
            keyDown.setIntegerValueField(.eventSourceUserData, value: repostTag)
            keyDown.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
                keyUp.flags = flags
                keyUp.setIntegerValueField(.eventSourceUserData, value: repostTag)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// The Chromium Shift+Enter newline, performed after the commit has been
    /// issued. Quirk apps (insertText("\n") submits there) get a replayed key
    /// press; everyone else gets the async "\n" insert.
    static func performChromiumNewline(keyCode: UInt16,
                                       client: any IMKTextInput,
                                       delay: TimeInterval) {
        if ChromiumDetector.frontmostAppTreatsNewlineInsertAsSubmit {
            postKeyPress(keyCode: keyCode, flags: .maskShift, after: delay)
        } else {
            let capturedClient = client
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                capturedClient.insertText("\n" as NSString,
                                          replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
    }
}
