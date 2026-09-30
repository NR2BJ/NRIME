import Cocoa
import InputMethodKit

/// Delivering a key to the frontmost application after committing composing
/// text.
///
/// Problem: When an IMKit input method calls `client.insertText()` inside `handle()`
/// and returns `false`, the original key event is not reliably forwarded to the host app
/// (especially in Electron-based apps like Slack, Discord, VS Code, Claude for Desktop).
///
/// Solution: Engines commit text, then post the key again. It comes back
/// through the input method like any key; nothing is composing by then, so
/// the engine passes it on to the app.
///
/// For Shift+Enter, most Chromium apps get `insertText("\n")` instead
/// (Shift+Return has no StandardKeyBinding.dict entry, so AppKit-driven paths
/// misinterpret a replayed key). Apps whose editor submits on a programmatic
/// "\n" (ChatGPT/Codex) get the replayed key press — with composition over,
/// the renderer's own keydown handler inserts the line break exactly as for a
/// physical Shift+Enter.
///
/// Both happen on the next turn of the run loop, after the key being handled
/// — Chromium drops a newline inserted inside it (oldHasMarkedText) — and
/// there is no other wait. Until 1.0.12-beta.4 the wait was a setting (15 ms,
/// and 120 ms for Codex) with ordering protection for keys typed during it;
/// those values were chosen while macOS was silently dropping the posted keys
/// for lack of permission, and once that was fixed no wait worked in Discord
/// and Codex (2026-09-30). The wait and its protection are in the git history.
enum KeyEventReposter {

#if DEBUG
    /// Test seam: captures posted keys instead of injecting real system events.
    static var captureForTesting: ((_ keyCode: UInt16, _ flags: CGEventFlags) -> Void)?
    /// Test seam: the answer `canPostEvents` gives under tests (granted unless set).
    static var postEventAccessForTesting: Bool?
#endif

    /// Whether NRIME may post key events. Without it macOS drops posted events
    /// silently — the commit happens and the key it was meant to deliver does not.
    ///
    /// The Device Control (Accessibility) grant is asked as well as the
    /// post-event check. CoreGraphics answers CGPreflightPostEventAccess once
    /// per process and repeats that answer: NRIME asked at launch, before the
    /// grant, and still said "denied" an hour after it was given — only a
    /// restart cleared it. AXIsProcessTrusted follows changes, and it is the
    /// grant that allows posting: macOS answers the post-event check from it
    /// (apps holding only that grant are allowed), and on macOS 27 "Device
    /// Control and Data Access" is the only switch there is.
    ///
    /// The cached answer is stale the other way too: turned off, the grant
    /// read "denied" through AXIsProcessTrusted while the preflight still said
    /// "allowed" (2026-09-30). So on macOS 27, where that one switch decides,
    /// only the live answer counts; before, a separate post-event grant may
    /// exist and the preflight is asked as well.
    static var canPostEvents: Bool {
#if DEBUG
        if AppGroupDefaults.isRunningTests {
            return postEventAccessForTesting ?? true
        }
#endif
        if AXIsProcessTrusted() { return true }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 { return false }
        return CGPreflightPostEventAccess()
    }

    /// Re-send a modifier shortcut (Cmd/Ctrl/Option+key) after the commit.
    /// Callers check `canPostEvents` first: when the event cannot be posted,
    /// handing the original key to the app beats consuming it for nothing.
    static func repost(_ event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
        postKeyPress(keyCode: event.keyCode, flags: flags)
    }

    /// The Chromium Shift+Enter newline, performed after the commit has been
    /// issued. Quirk apps (insertText("\n") submits there) get a replayed key
    /// press; everyone else gets the "\n" insert.
    static func performChromiumNewline(keyCode: UInt16, client: any IMKTextInput) {
        if ChromiumDetector.frontmostAppTreatsNewlineInsertAsSubmit {
            // Without permission the replayed key is dropped, and inserting
            // "\n" instead would send the message. Commit only; pressing
            // Shift+Enter again gives the newline.
            guard canPostEvents else {
                DeveloperLogger.shared.log("Reposter", "Newline replay skipped: no post-event access")
                return
            }
            // The Shift flag is deliberate: a plain Enter would submit.
            postKeyPress(keyCode: keyCode, flags: .maskShift)
            DeveloperLogger.shared.log("Reposter", "Newline replayed as a key press")
        } else {
            DispatchQueue.main.async {
                client.insertText("\n" as NSString,
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
                DeveloperLogger.shared.log("Reposter", "Newline inserted")
            }
        }
    }

    /// Post a key press (down, then up) on the next turn of the run loop.
    ///
    /// The event source is `.hidSystemState` rather than nil: an event built
    /// with no source carries no HID state, and Chromium renderers can treat it
    /// differently from a real key press (the March experiments, where CGEvent
    /// replay "only committed", used a nil source).
    private static func postKeyPress(keyCode: UInt16, flags: CGEventFlags) {
#if DEBUG
        // Taken now, so the key reaches the test that posted it.
        let capture = captureForTesting
#endif
        DispatchQueue.main.async {
#if DEBUG
            if let capture {
                capture(keyCode, flags)
                return
            }
            // Tests must never type into the user's session.
            if AppGroupDefaults.isRunningTests { return }
#endif
            let source = CGEventSource(stateID: .hidSystemState)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source,
                                          virtualKey: keyCode,
                                          keyDown: isDown) else { continue }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
