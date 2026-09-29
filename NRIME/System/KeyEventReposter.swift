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
    /// Test seam: captures replay sequences (the newline, then held keys) with their tags.
    static var sequenceCaptureForTesting: ((_ keys: [(keyCode: UInt16, flags: CGEventFlags, tag: Int64)]) -> Void)?
    /// Test seam: the answer `canPostEvents` gives under tests (granted unless set).
    static var postEventAccessForTesting: Bool?
    /// Test seam: the frontmost app the replay compares against (the real one unless set).
    static var frontmostBundleIDForTesting: String??
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
    static var canPostEvents: Bool {
#if DEBUG
        if AppGroupDefaults.isRunningTests {
            return postEventAccessForTesting ?? true
        }
#endif
        return CGPreflightPostEventAccess() || AXIsProcessTrusted()
    }

    /// Re-send a modifier shortcut (Cmd/Ctrl/Option+key) after the commit.
    /// Callers check `canPostEvents` first: when the event cannot be posted,
    /// handing the original key to the app beats consuming it for nothing.
    static func repost(_ event: NSEvent, after delay: TimeInterval) {
        let flags = CGEventFlags(rawValue: UInt64(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
        postKeyPress(keyCode: event.keyCode, flags: flags, after: delay)
    }

    /// Post a tagged key press (down+up) after a delay. The controller sees the
    /// tag and passes the event straight through to the host app.
    ///
    /// The event source is `.hidSystemState` rather than nil: an event built
    /// with no source carries no HID state, and Chromium renderers can treat it
    /// differently from a real key press (the March experiments, where CGEvent
    /// replay "only committed", used a nil source).
    static func postKeyPress(keyCode: UInt16, flags: CGEventFlags, after delay: TimeInterval) {
#if DEBUG
        // Taken when scheduled, so a delayed repost reaches the test that made
        // it rather than whichever test is running when it fires.
        let capture = captureForTesting
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
#if DEBUG
            if let capture {
                capture(keyCode, flags)
                return
            }
            // Tests must never type into the user's session.
            if AppGroupDefaults.isRunningTests { return }
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

    /// How long the Codex replay waits for the commit to settle — its own
    /// setting, not the Electron Shift+Enter delay. The renderer has to apply
    /// the committed text before it reads the key as a plain Shift+Enter.
    static var replayDelay: TimeInterval { Settings.shared.codexNewlineDelay }

    /// The Chromium Shift+Enter newline, performed after the commit has been
    /// issued. Quirk apps (insertText("\n") submits there) get a replayed key
    /// press; everyone else gets the async "\n" insert.
    static func performChromiumNewline(keyCode: UInt16,
                                       client: any IMKTextInput,
                                       delay: TimeInterval) {
        if ChromiumDetector.frontmostAppTreatsNewlineInsertAsSubmit {
            // Without permission the replayed key is dropped, and inserting
            // "\n" instead would send the message. Commit only; pressing
            // Shift+Enter again gives the newline.
            guard canPostEvents else {
                DeveloperLogger.shared.log("Reposter", "Newline replay skipped: no post-event access")
                return
            }
            scheduleReplay(keyCode: keyCode, client: client, after: replayDelay)
        } else {
            scheduleNewlineInsert(into: client, after: delay)
        }
    }

    // MARK: - Pending replay (Codex)

    /// Tag on keys posted again after a replay (see `holdForPendingReplay`).
    /// The controller routes them to the engine as usual, but does not show
    /// them to the shortcut handler a second time.
    static let heldKeyTag: Int64 = 0x4E52494D46

    private struct HeldKey {
        let keyCode: UInt16
        let flags: CGEventFlags
    }

    /// A replayed Shift+Enter waiting out its delay, and the keys typed meanwhile.
    ///
    /// Those keys are held instead of handled. The replay is a posted event, so
    /// anything the input method inserts directly lands before it: typing on
    /// right after Shift+Enter put the next word above the line break. When the
    /// replay fires, the held keys are posted right after it, in order, and
    /// come back through the input method as ordinary keystrokes.
    private struct PendingReplay {
        let keyCode: UInt16
        let client: any IMKTextInput
        let clientID: ObjectIdentifier
        let bundleID: String?
        let delay: TimeInterval
        let scheduledAt: TimeInterval
        var held: [HeldKey] = []
        var work: DispatchWorkItem?
#if DEBUG
        /// Taken when scheduled, so a replay reaches the test that made it.
        var capture: (([(keyCode: UInt16, flags: CGEventFlags, tag: Int64)]) -> Void)?
#endif
    }

    /// Main-thread only: scheduled from handle() and fired on the main queue.
    private static var pendingReplay: PendingReplay?

    /// Key presses the controller has seen — to tell whether the caret moved
    /// because of the replay alone.
    private static var keyDownCount = 0

    static func noteKeyDown() {
        keyDownCount &+= 1
    }

    private static var frontmostBundleID: String? {
#if DEBUG
        if let forced = frontmostBundleIDForTesting { return forced }
#endif
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private static func scheduleReplay(keyCode: UInt16, client: any IMKTextInput,
                                       after delay: TimeInterval) {
        // An earlier replay belongs before this one.
        firePendingReplay(reason: "superseded")

        var replay = PendingReplay(keyCode: keyCode,
                                   client: client,
                                   clientID: ObjectIdentifier(client as AnyObject),
                                   bundleID: frontmostBundleID,
                                   delay: delay,
                                   scheduledAt: ProcessInfo.processInfo.systemUptime)
#if DEBUG
        if let sequence = sequenceCaptureForTesting {
            replay.capture = sequence
        } else if let single = captureForTesting {
            replay.capture = { keys in keys.forEach { single($0.keyCode, $0.flags) } }
        }
#endif
        let work = DispatchWorkItem { firePendingReplay(reason: "timer") }
        replay.work = work
        pendingReplay = replay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Hold a key press that arrives while a replay waits, to post it after the
    /// newline. False when nothing waits — handle the key as usual. A key in
    /// another text field fires the replay now instead: it was not typed after
    /// that newline.
    static func holdForPendingReplay(_ event: NSEvent, client: AnyObject) -> Bool {
        guard event.type == .keyDown, var replay = pendingReplay else { return false }
        guard replay.clientID == ObjectIdentifier(client) else {
            firePendingReplay(reason: "otherClient")
            return false
        }
        let flags = event.cgEvent?.flags ?? CGEventFlags(rawValue: UInt64(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
        replay.held.append(HeldKey(keyCode: event.keyCode, flags: flags))
        pendingReplay = replay
        return true
    }

    /// Post the waiting replay now, followed by any held keys. The newline is
    /// skipped when its app is no longer in front (it would land in another
    /// app); held keys are posted either way, so nothing typed is lost.
    /// No-op when nothing waits.
    static func firePendingReplay(reason: String) {
        guard let replay = pendingReplay else { return }
        pendingReplay = nil
        replay.work?.cancel()

        let sameApp = frontmostBundleID == replay.bundleID
        var keys: [(keyCode: UInt16, flags: CGEventFlags, tag: Int64)] = []
        if sameApp {
            keys.append((replay.keyCode, .maskShift, repostTag))
        }
        keys += replay.held.map { ($0.keyCode, $0.flags, heldKeyTag) }

        // The caret moves one character when the newline goes in — the only
        // way to see from here whether Codex took it. Held keys move it too,
        // so only a replay with none is judged.
        let caretBefore = sameApp && replay.held.isEmpty ? caretLocation(of: replay.client) : nil
        let keysBefore = keyDownCount
#if DEBUG
        postKeySequence(keys, capture: replay.capture)
#else
        postKeySequence(keys)
#endif

        var metadata = [
            "delayMs": String(format: "%.0f", replay.delay * 1000),
            "waitedMs": String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - replay.scheduledAt) * 1000),
            "reason": reason,
            "held": "\(replay.held.count)",
            "sent": sameApp ? "Y" : "N",
        ]
        guard let caretBefore else {
            DeveloperLogger.shared.log("Reposter", "Codex newline", metadata: metadata)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let caretAfter = caretLocation(of: replay.client)
            let verdict: String
            if keyDownCount != keysBefore {
                verdict = "?" // the user typed on; the caret moved for that too
            } else if caretAfter == caretBefore + 1 {
                verdict = "Y"
            } else if caretAfter == caretBefore {
                verdict = "N"
            } else {
                verdict = "?"
            }
            metadata["caret"] = "\(caretBefore)→\(caretAfter.map(String.init) ?? "-")"
            metadata["newline"] = verdict
            DeveloperLogger.shared.log("Reposter", "Codex newline", metadata: metadata)
        }
    }

    private static func caretLocation(of client: any IMKTextInput) -> Int? {
        let range = client.selectedRange()
        return range.location == NSNotFound ? nil : range.location
    }

    /// Post key presses (down, then up) in order, each with its tag.
    private static func postKeySequence(
        _ keys: [(keyCode: UInt16, flags: CGEventFlags, tag: Int64)],
        capture: (([(keyCode: UInt16, flags: CGEventFlags, tag: Int64)]) -> Void)? = nil
    ) {
        guard !keys.isEmpty else { return }
#if DEBUG
        if let capture {
            capture(keys)
            return
        }
        // Tests must never type into the user's session.
        if AppGroupDefaults.isRunningTests { return }
#endif
        let source = CGEventSource(stateID: .hidSystemState)
        for key in keys {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source,
                                          virtualKey: key.keyCode,
                                          keyDown: isDown) else { continue }
                event.flags = key.flags
                event.setIntegerValueField(.eventSourceUserData, value: key.tag)
                event.post(tap: .cghidEventTap)
            }
        }
    }

#if DEBUG
    /// Drop anything still waiting, so one test's replay cannot fire in the next.
    static func resetPendingForTesting() {
        pendingReplay?.work?.cancel()
        pendingReplay = nil
        pendingNewline?.work.cancel()
        pendingNewline = nil
    }
#endif

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
