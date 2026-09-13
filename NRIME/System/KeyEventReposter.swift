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
    ///
    /// The event source is `.hidSystemState` rather than nil: an event built
    /// with no source carries no HID state, and Chromium renderers can treat it
    /// differently from a real key press (the March experiments, where CGEvent
    /// replay "only committed", used a nil source).
    static func postKeyPress(keyCode: UInt16, flags: CGEventFlags, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
#if DEBUG
            if let capture = captureForTesting {
                capture(keyCode, flags)
                return
            }
#endif
            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
            keyDown.flags = flags
            keyDown.setIntegerValueField(.eventSourceUserData, value: repostTag)
            keyDown.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
                keyUp.flags = flags
                keyUp.setIntegerValueField(.eventSourceUserData, value: repostTag)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    /// A replayed key needs longer than an insertText does: the renderer has to
    /// finish applying the committed text and settle its composition state
    /// before it will treat the key as a plain Shift+Enter. The shiftEnterDelay
    /// slider tops out at 50ms, which measured too short here.
    static let replayDelay: TimeInterval = 0.12

    /// The Chromium Shift+Enter newline, performed after the commit has been
    /// issued. Quirk apps (insertText("\n") submits there) get a replayed key
    /// press; everyone else gets the async "\n" insert.
    static func performChromiumNewline(keyCode: UInt16,
                                       client: any IMKTextInput,
                                       delay: TimeInterval) {
        if ChromiumDetector.frontmostAppTreatsNewlineInsertAsSubmit {
            postKeyPress(keyCode: keyCode, flags: .maskShift,
                         after: max(delay, replayDelay))
        } else {
            scheduleNewlineInsert(into: client, after: delay)
        }
    }

    // MARK: - Pending newline

    /// A newline waiting out the oldHasMarkedText delay.
    ///
    /// It inserts with an NSNotFound replacement range, which replaces whatever
    /// marked text is active when it lands — so if the user starts the next
    /// word inside the delay, the newline eats that composition instead of
    /// following the committed text. Keeping the work item here lets the
    /// controller deliver it in order before handling the next key, rather than
    /// cancelling it and losing the newline outright.
    private struct PendingNewline {
        let client: any IMKTextInput
        let work: DispatchWorkItem
    }

    /// Main-thread only: scheduled from handle() and fired on the main queue.
    private static var pendingNewline: PendingNewline?

    private static func scheduleNewlineInsert(into client: any IMKTextInput,
                                              after delay: TimeInterval) {
        // Only one can be outstanding; an earlier one belongs before this key.
        flushPendingNewline()

        let work = DispatchWorkItem {
            guard pendingNewline != nil else { return }
            pendingNewline = nil
            insertNewline(into: client)
        }
        pendingNewline = PendingNewline(client: client, work: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Deliver a scheduled newline now, before anything else can start a new
    /// composition for it to overwrite. No-op when nothing is pending.
    static func flushPendingNewline() {
        guard let pending = pendingNewline else { return }
        pendingNewline = nil
        pending.work.cancel()
        insertNewline(into: pending.client)
    }

    private static func insertNewline(into client: any IMKTextInput) {
        client.insertText("\n" as NSString,
                          replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}
