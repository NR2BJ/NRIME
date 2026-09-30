import Cocoa
import InputMethodKit

/// Delivering a key to the frontmost application after committing composing
/// text.
///
/// Problem: When an IMKit input method calls `client.insertText()` inside `handle()`
/// and returns `false`, the original key event is not reliably forwarded to the host app
/// (especially in Electron-based apps like Slack, Discord, VS Code, Claude for Desktop).
///
/// Solution: Engines commit text, then post the key again after a short wait.
/// It comes back through the input method like any key; nothing is composing
/// by then, so the engine passes it on to the app.
///
/// For Shift+Enter, most Chromium apps get `insertText("\n")` instead
/// (Shift+Return has no StandardKeyBinding.dict entry, so AppKit-driven paths
/// misinterpret a replayed key). Apps whose editor submits on a programmatic
/// "\n" (ChatGPT/Codex) get the replayed key press — with composition over,
/// the renderer's own keydown handler inserts the line break exactly as for a
/// physical Shift+Enter.
///
/// Both wait a little after the commit (`insertWait`, `keyPressWait`). The
/// wait was removed in 1.0.12-beta.5 (no wait worked in Discord and Codex on
/// the owner's Mac) and came back the same day: on a slower MacBook the
/// syllable being composed was lost — every time in Claude, now and then in
/// Codex — because the newline or the replayed key reached the app's editor
/// before it had finished taking the commit. Before beta.5, Claude with the
/// 15 ms wait never lost it. The ordering protection came back with it: a key
/// typed during the wait still lands after the newline.
enum KeyEventReposter {

#if DEBUG
    /// Test seam: captures posted keys instead of injecting real system events.
    static var captureForTesting: ((_ keyCode: UInt16, _ flags: CGEventFlags) -> Void)?
    /// Test seam: captures replay sequences (the newline, then held keys).
    static var sequenceCaptureForTesting: ((_ keys: [(keyCode: UInt16, flags: CGEventFlags)]) -> Void)?
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

    // MARK: - Waits

    /// How long the inserted "\n" — and a re-sent ⌘ shortcut — waits after
    /// the commit. 15 ms held for months in Claude; a little more for a slower Mac.
    static var insertWait: TimeInterval {
        Settings.shared.newlineWaitOverride("newlineInsertWaitMs") ?? 0.02
    }

    /// How long the replayed Shift+Enter waits after the commit (Codex). With
    /// no wait the owner's MacBook lost the syllable now and then.
    static var keyPressWait: TimeInterval {
        Settings.shared.newlineWaitOverride("newlineKeyPressWaitMs") ?? 0.05
    }

    // MARK: - Posting

    /// Re-send a modifier shortcut (Cmd/Ctrl/Option+key) after the commit.
    /// Callers check `canPostEvents` first: when the event cannot be posted,
    /// handing the original key to the app beats consuming it for nothing.
    static func repost(_ event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue))
#if DEBUG
        // Taken now, so the key reaches the test that posted it.
        let capture = captureForTesting
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + insertWait) {
#if DEBUG
            if let capture {
                capture(event.keyCode, flags)
                return
            }
#endif
            postKeySequence([(event.keyCode, flags)])
        }
    }

    /// The Chromium Shift+Enter newline, performed after the commit has been
    /// issued. Key-press apps (ChromiumDetector) get a replayed key press;
    /// everyone else gets the "\n" insert.
    static func performChromiumNewline(keyCode: UInt16, client: any IMKTextInput) {
        if ChromiumDetector.frontmostAppNeedsNewlineKeyPress {
            // Without permission the replayed key is dropped, and inserting
            // "\n" instead would send the message. Commit only; pressing
            // Shift+Enter again gives the newline.
            guard canPostEvents else {
                DeveloperLogger.shared.log("Reposter", "Newline replay skipped: no post-event access")
                return
            }
            scheduleReplay(keyCode: keyCode, client: client, after: keyPressWait)
        } else {
            scheduleNewlineInsert(into: client, after: insertWait)
        }
    }

    /// Post key presses (down, then up) in order.
    ///
    /// The event source is `.hidSystemState` rather than nil: an event built
    /// with no source carries no HID state, and Chromium renderers can treat it
    /// differently from a real key press (the March experiments, where CGEvent
    /// replay "only committed", used a nil source).
    private static func postKeySequence(_ keys: [(keyCode: UInt16, flags: CGEventFlags)]) {
        guard !keys.isEmpty else { return }
#if DEBUG
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
                event.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Pending replay (key-press apps)

    /// A replayed Shift+Enter waiting out its wait, and the keys typed meanwhile.
    ///
    /// Those keys are held instead of handled. The replay is a posted event, so
    /// anything the input method inserts directly lands before it: typing on
    /// right after Shift+Enter put the next word above the line break. When the
    /// replay fires, the held keys are posted right after it, in order, and
    /// come back through the input method as ordinary keystrokes.
    private struct PendingReplay {
        let keyCode: UInt16
        let clientID: ObjectIdentifier
        let bundleID: String?
        let scheduledAt: TimeInterval
        var held: [(keyCode: UInt16, flags: CGEventFlags)] = []
        var work: DispatchWorkItem?
#if DEBUG
        /// Taken when scheduled, so a replay reaches the test that made it.
        var capture: (([(keyCode: UInt16, flags: CGEventFlags)]) -> Void)?
#endif
    }

    /// Main-thread only: scheduled from handle() and fired on the main queue.
    private static var pendingReplay: PendingReplay?

    private static var frontmostBundleID: String? {
#if DEBUG
        if let forced = frontmostBundleIDForTesting { return forced }
#endif
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private static func scheduleReplay(keyCode: UInt16, client: any IMKTextInput,
                                       after wait: TimeInterval) {
        // An earlier replay belongs before this one.
        firePendingReplay(reason: "superseded")

        var replay = PendingReplay(keyCode: keyCode,
                                   clientID: ObjectIdentifier(client as AnyObject),
                                   bundleID: frontmostBundleID,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
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
        replay.held.append((event.keyCode, flags))
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
        var keys: [(keyCode: UInt16, flags: CGEventFlags)] = []
        if sameApp {
            // The Shift flag is deliberate: a plain Enter would submit.
            keys.append((replay.keyCode, .maskShift))
        }
        keys += replay.held
#if DEBUG
        if let capture = replay.capture {
            capture(keys)
        } else {
            postKeySequence(keys)
        }
#else
        postKeySequence(keys)
#endif
        DeveloperLogger.shared.log("Reposter", "Newline replayed as a key press", metadata: [
            "waitedMs": String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - replay.scheduledAt) * 1000),
            "reason": reason,
            "held": "\(replay.held.count)",
            "sent": sameApp ? "Y" : "N",
        ])
    }

    // MARK: - Pending newline (inserted "\n")

    /// A newline waiting out its wait.
    ///
    /// It inserts with an NSNotFound replacement range, which replaces whatever
    /// marked text is active when it lands — so if the user starts the next
    /// word inside the wait, the newline would eat that composition. Keeping
    /// the work item here lets the controller deliver it before handling the
    /// next key (`flushPendingNewline`), in the order it was typed.
    private struct PendingNewline {
        let client: any IMKTextInput
        let work: DispatchWorkItem
        let scheduledAt: TimeInterval
    }

    /// Main-thread only: scheduled from handle() and fired on the main queue.
    private static var pendingNewline: PendingNewline?

    private static func scheduleNewlineInsert(into client: any IMKTextInput,
                                              after wait: TimeInterval) {
        // Only one can be outstanding; an earlier one belongs before this key.
        flushPendingNewline()

        let work = DispatchWorkItem {
            guard let pending = pendingNewline else { return }
            pendingNewline = nil
            insertNewline(pending, reason: "timer")
        }
        pendingNewline = PendingNewline(client: client, work: work,
                                        scheduledAt: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// Deliver a waiting newline now, before anything else can start a new
    /// composition for it to overwrite. No-op when nothing is pending.
    static func flushPendingNewline() {
        guard let pending = pendingNewline else { return }
        pendingNewline = nil
        pending.work.cancel()
        insertNewline(pending, reason: "nextKey")
    }

    private static func insertNewline(_ pending: PendingNewline, reason: String) {
        pending.client.insertText("\n" as NSString,
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
        DeveloperLogger.shared.log("Reposter", "Newline inserted", metadata: [
            "waitedMs": String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - pending.scheduledAt) * 1000),
            "reason": reason,
        ])
    }

#if DEBUG
    /// Drop anything still waiting, so one test's newline cannot fire in the next.
    static func resetPendingForTesting() {
        pendingReplay?.work?.cancel()
        pendingReplay = nil
        pendingNewline?.work.cancel()
        pendingNewline = nil
    }
#endif
}
