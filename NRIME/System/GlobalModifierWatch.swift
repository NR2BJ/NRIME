import ApplicationServices
import Cocoa

// MARK: - Clean-tap judgment

/// Finds clean solo taps of modifier keys in the system-wide event stream:
/// the key goes down with no other modifier held and comes up with no key,
/// click or other modifier in between. Pure state — fed by the event tap,
/// testable on its own.
///
/// Repeats are dropped: some setups deliver each modifier change twice,
/// 5–20 ms apart (seen in the developer log in November 2026, about one
/// Shift event in five). A second press of a key already down, or a release
/// of a key already up, is the same gesture again.
struct GlobalTapJudge {
    struct Event {
        enum Kind { case flags, keyDown, pointer }
        let kind: Kind
        let keyCode: UInt16
        /// Raw modifier flags, device-dependent side bits included.
        let flags: UInt64
        /// Seconds on the NSEvent.timestamp clock.
        let timestamp: TimeInterval
    }

    struct Tap: Equatable {
        let keyCode: UInt16
        let down: TimeInterval
        let release: TimeInterval
        var held: TimeInterval { release - down }
    }

    enum Outcome: Equatable {
        case none
        case tap(Tap)
        case repeated(keyCode: UInt16, gap: TimeInterval)
    }

    /// A second press of a key already down this soon is the same press again;
    /// later than this, its release was lost and this is a new press.
    static let repeatWindow: TimeInterval = 0.05

    /// Modifier keys down, with when they went down.
    private var held: [UInt16: TimeInterval] = [:]
    /// The press being watched for a solo tap.
    private var gesture: (keyCode: UInt16, down: TimeInterval, clean: Bool)?

    mutating func feed(_ event: Event) -> Outcome {
        switch event.kind {
        case .keyDown, .pointer:
            gesture?.clean = false
            return .none
        case .flags:
            return feedFlags(event)
        }
    }

    private mutating func feedFlags(_ event: Event) -> Outcome {
        guard let sides = ShortcutHandler.deviceModifierMasks(for: event.keyCode) else {
            return .none // Caps Lock, Fn: not modifier taps
        }
        // Without side bits (synthetic events) the press cannot be told from
        // its twin's; judge nothing, but the gesture is no clean tap either.
        guard event.flags & Self.allSides != 0 || held[event.keyCode] != nil else {
            gesture?.clean = false
            return .none
        }
        let side = UInt64(sides.requiredSide)
        let isDown = (event.flags & side) != 0
        let key = event.keyCode

        if isDown {
            if let since = held[key] {
                let gap = event.timestamp - since
                if gap >= 0, gap < Self.repeatWindow {
                    return .repeated(keyCode: key, gap: gap)
                }
            }
            held[key] = event.timestamp
            // Another modifier joining spoils the tap being watched.
            if let current = gesture, current.keyCode != key {
                gesture?.clean = false
            }
            gesture = (key, event.timestamp, !Self.otherModifiersDown(event.flags, besides: side))
            return .none
        }

        guard held.removeValue(forKey: key) != nil else {
            return .repeated(keyCode: key, gap: 0)
        }
        guard let current = gesture, current.keyCode == key else { return .none }
        gesture = nil
        let tap = Tap(keyCode: key, down: current.down, release: event.timestamp)
        guard current.clean, tap.held >= 0,
              !Self.otherModifiersDown(event.flags, besides: side) else { return .none }
        return .tap(tap)
    }

    /// Device-dependent bits of both sides of Shift, Control, Option, Command.
    private static let allSides: UInt64 = 0x2 | 0x4 | 0x1 | 0x2000 | 0x20 | 0x40 | 0x8 | 0x10

    /// Whether Shift, Control, Option or Command — any side but `side` — is down.
    private static func otherModifiersDown(_ flags: UInt64, besides side: UInt64) -> Bool {
        flags & allSides & ~side != 0
    }
}

// MARK: - Who handled a release

/// Which modifier releases the input method's own path (IMKit → the
/// controller's ShortcutHandler) has seen, and which taps the global watch
/// fired. Each path checks the other before switching, so one release never
/// switches twice. Main thread only.
enum TapReleaseLedger {
    /// Two releases of the same key closer than this are the same release
    /// (repeats arrive within 20 ms; two real taps are farther apart).
    static let sameReleaseWindow: TimeInterval = 0.03

    private enum Kind { case imkTracked, imkUntracked, global }
    /// `seenAt`: when the entry was made (uptime), not when the key moved.
    private static var entries: [(keyCode: UInt16, timestamp: TimeInterval, kind: Kind, seenAt: TimeInterval)] = []

    /// The input method's path saw this release. `tracked`: it had the press
    /// too, so it decided tap or not; untracked, it could not.
    static func noteIMKRelease(keyCode: UInt16, timestamp: TimeInterval, tracked: Bool) {
        append(keyCode, timestamp, tracked ? .imkTracked : .imkUntracked)
    }

    static func noteGlobalFire(keyCode: UInt16, timestamp: TimeInterval) {
        append(keyCode, timestamp, .global)
    }

    /// The input method's path decided this release itself.
    static func decidedByIMK(keyCode: UInt16, near timestamp: TimeInterval) -> Bool {
        contains(keyCode, timestamp, .imkTracked)
    }

    /// How far the input method's record of this release is from `timestamp`
    /// — diagnostics: both should be the same event on the same clock.
    static func imkOffset(keyCode: UInt16, near timestamp: TimeInterval) -> TimeInterval? {
        entries.first {
            $0.keyCode == keyCode && $0.kind == .imkTracked
                && abs($0.timestamp - timestamp) < sameReleaseWindow
        }.map { $0.timestamp - timestamp }
    }

    /// The global watch already switched for this release.
    static func firedGlobally(keyCode: UInt16, near timestamp: TimeInterval) -> Bool {
        contains(keyCode, timestamp, .global)
    }

    /// The input method's path decided a release of this key within the last
    /// `seconds` of real time. Safety net for the clocks: if they ever
    /// disagree, timestamps stop matching, and without this every tap would
    /// switch twice.
    static func imkDecidedRecently(keyCode: UInt16, within seconds: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return entries.contains { $0.keyCode == keyCode && $0.kind == .imkTracked && now - $0.seenAt < seconds }
    }

    private static func append(_ keyCode: UInt16, _ timestamp: TimeInterval, _ kind: Kind) {
        entries.append((keyCode, timestamp, kind, ProcessInfo.processInfo.systemUptime))
        if entries.count > 32 { entries.removeFirst(entries.count - 32) }
    }

    private static func contains(_ keyCode: UInt16, _ timestamp: TimeInterval, _ kind: Kind) -> Bool {
        entries.contains {
            $0.keyCode == keyCode && $0.kind == kind && abs($0.timestamp - timestamp) < sameReleaseWindow
        }
    }

#if DEBUG
    static func resetForTesting() { entries = [] }
#endif
}

// MARK: - The watch

/// Watches modifier keys system-wide, so a Shift tap switches the language
/// even when the input method never hears of it. IMKit only sends keys to
/// the input method while a text field is active; a tap just after switching
/// windows, or with focus outside any field, was simply lost.
///
/// The input method's own path stays in charge: a tap is switched here only
/// when that path did not see the release (TapReleaseLedger), either a moment
/// later or as soon as the next key reaches the input method, whichever
/// comes first. Needs the Accessibility (Device Control) grant; without it
/// nothing changes from before.
final class GlobalModifierWatch {
    static let shared = GlobalModifierWatch()

    /// How long the input method's path gets to report a release before the
    /// watch takes the tap as missed. Its events normally arrive within a few
    /// milliseconds; a stalled main thread is covered by the ledger both ways.
    static let grace: TimeInterval = 0.1

    /// Switches the language for a missed tap. Replaceable in tests.
    static var performAction: (ShortcutHandler.Action) -> Void = { action in
        NRIMEInputController.performMissedTap(action)
    }

    private let lock = NSLock()
    private var judge = GlobalTapJudge()   // tap thread, under lock
    private var pending: [GlobalTapJudge.Tap] = []   // under lock
    private var port: CFMachPort?   // under lock
    private var clockMismatchLogged = false   // under lock
    private var thread: Thread?   // main
    private var observingPermission = false   // main
    private var matchesLogged = 0   // main

    private init() {}

    // MARK: Start

    /// Start watching if the grant allows it; otherwise try again when the
    /// permissions change. Main thread.
    func start() {
        guard !AppGroupDefaults.isRunningTests, thread == nil else { return }
        observePermissionChanges()
        let listenOnly = CGPreflightListenEventAccess()
        guard listenOnly || AXIsProcessTrusted() else {
            DeveloperLogger.shared.log("GlobalTap", "Not started", metadata: ["reason": "noPermission"])
            return
        }
        let thread = Thread { [weak self] in self?.runTap(listenOnly: listenOnly) }
        thread.name = "NRIME global modifier watch"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func observePermissionChanges() {
        guard !observingPermission else { return }
        observingPermission = true
        DistributedNotificationCenter.default().addObserver(
            forName: PermissionStatus.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    private func runTap(listenOnly: Bool) {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: listenOnly ? .listenOnly : .defaultTap,
                                           eventsOfInterest: mask, callback: globalModifierTapCallback,
                                           userInfo: me) else {
            DispatchQueue.main.async {
                self.thread = nil
                DeveloperLogger.shared.log("GlobalTap", "Not started", metadata: [
                    "reason": "tapCreateFailed", "listenOnly": "\(listenOnly)",
                ])
            }
            return
        }
        lock.lock(); self.port = port; lock.unlock()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        DispatchQueue.main.async {
            DeveloperLogger.shared.log("GlobalTap", "Started", metadata: ["listenOnly": "\(listenOnly)"])
        }
        CFRunLoopRun()
    }

    // MARK: Events (tap thread)

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let port = self.port; lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            DispatchQueue.main.async {
                DeveloperLogger.shared.log("GlobalTap", "Re-enabled", metadata: [
                    "reason": type == .tapDisabledByTimeout ? "timeout" : "userInput",
                ])
            }
            return
        }
        let kind: GlobalTapJudge.Event.Kind
        switch type {
        case .flagsChanged: kind = .flags
        case .keyDown: kind = .keyDown
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .pointer
        default: return
        }
        // The ledger matches this time against the input method's own events;
        // a time that is not on their clock could let one tap switch twice.
        // An event happened a moment ago — far from now, the unit is unknown.
        let now = ProcessInfo.processInfo.systemUptime
        let timestamp = Self.seconds(fromEventTimestamp: event.timestamp, now: now)
        guard abs(now - timestamp) < 1 else {
            lock.lock()
            let first = !clockMismatchLogged
            clockMismatchLogged = true
            lock.unlock()
            if first {
                DispatchQueue.main.async {
                    DeveloperLogger.shared.log("GlobalTap", "Event clock not understood; ignoring events", metadata: [
                        "raw": "\(event.timestamp)", "now": String(format: "%.3f", now),
                    ])
                }
            }
            return
        }
        let judged = GlobalTapJudge.Event(
            kind: kind,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            timestamp: timestamp)
        lock.lock()
        let outcome = judge.feed(judged)
        if case .tap(let tap) = outcome { pending.append(tap) }
        lock.unlock()

        switch outcome {
        case .tap:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace) { [weak self] in
                self?.resolve(before: nil, excludingKey: nil, via: "wait")
            }
        case .repeated(let keyCode, let gap):
            DispatchQueue.main.async {
                guard DeveloperLogger.shared.isEnabled,
                      ShortcutHandler.modifierTapAction(for: keyCode) != nil else { return }
                DeveloperLogger.shared.log("GlobalTap", "Repeated modifier event", metadata: [
                    "key": ShortcutHandler.keyName(keyCode), "gapMs": ShortcutHandler.ms(gap),
                ])
            }
        case .none:
            break
        }
    }

    /// CGEvent timestamps are documented as nanoseconds but have been machine
    /// ticks on some systems (which differ on Apple silicon, 125/3 ns). The
    /// event happened a moment ago, so whichever reading lands near `now`
    /// (NSEvent.timestamp's clock) is the right one.
    static func seconds(fromEventTimestamp raw: CGEventTimestamp, now: TimeInterval,
                        timebase: mach_timebase_info_data_t = machTimebase) -> TimeInterval {
        let asNanoseconds = Double(raw) / 1e9
        let asTicks = Double(raw) * Double(timebase.numer) / Double(timebase.denom) / 1e9
        return abs(now - asTicks) < abs(now - asNanoseconds) ? asTicks : asNanoseconds
    }

    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: Deciding (main thread)

    /// Settle the watched taps that came before `event` — called as each key
    /// reaches the input method, so a missed tap switches before the next
    /// letter is typed. A flagsChanged event is excluded as its own release.
    func settle(before event: NSEvent) {
        guard event.type == .keyDown || event.type == .flagsChanged else { return }
        resolve(before: event.timestamp,
                excludingKey: event.type == .flagsChanged ? event.keyCode : nil,
                via: "nextKey")
    }

    /// Decide pending taps: those released before `limit`, or (no limit) those
    /// older than the grace period.
    func resolve(before limit: TimeInterval?, excludingKey: UInt16?, via: String,
                 now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        var due: [GlobalTapJudge.Tap] = []
        pending.removeAll { tap in
            let isDue: Bool
            if let limit {
                let isThisEvent = tap.keyCode == excludingKey
                    && abs(tap.release - limit) < TapReleaseLedger.sameReleaseWindow
                isDue = tap.release < limit && !isThisEvent
            } else {
                isDue = now - tap.release >= Self.grace
            }
            if isDue { due.append(tap) }
            return isDue
        }
        lock.unlock()
        for tap in due { decide(tap, via: via, now: now) }
    }

    private func decide(_ tap: GlobalTapJudge.Tap, via: String, now: TimeInterval) {
        guard let action = ShortcutHandler.modifierTapAction(for: tap.keyCode),
              action == .toggleEnglish || action == .toggleNonEnglish else { return }
        // The usual case: the input method had the whole gesture. The first
        // matches are logged with their offset, to show the clocks agree.
        if let offset = TapReleaseLedger.imkOffset(keyCode: tap.keyCode, near: tap.release) {
            if matchesLogged < 20 {
                matchesLogged += 1
                DeveloperLogger.shared.log("GlobalTap", "Matched input method release", metadata: [
                    "key": ShortcutHandler.keyName(tap.keyCode),
                    "offsetUs": String(format: "%.0f", offset * 1e6),
                ])
            }
            return
        }
        if TapReleaseLedger.firedGlobally(keyCode: tap.keyCode, near: tap.release) { return }
        if TapReleaseLedger.imkDecidedRecently(keyCode: tap.keyCode, within: 0.5) {
            DeveloperLogger.shared.log("GlobalTap", "Missed tap ignored", metadata: [
                "key": ShortcutHandler.keyName(tap.keyCode), "reason": "inputMethodJustDecided",
            ])
            return
        }

        var metadata = [
            "key": ShortcutHandler.keyName(tap.keyCode),
            "heldMs": ShortcutHandler.ms(tap.held),
            "lateMs": ShortcutHandler.ms(now - tap.release),
            "via": via,
            "app": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
        ]
        guard tap.held < Settings.shared.tapThreshold else {
            metadata["reason"] = "tooLong"
            DeveloperLogger.shared.log("GlobalTap", "Missed tap ignored", metadata: metadata)
            return
        }
        guard InputSourceSelector.currentInputSourceID()?.hasPrefix(InputSourceSelector.bundleID) ?? false else {
            metadata["reason"] = "otherInputSource"
            DeveloperLogger.shared.log("GlobalTap", "Missed tap ignored", metadata: metadata)
            return
        }
        TapReleaseLedger.noteGlobalFire(keyCode: tap.keyCode, timestamp: tap.release)
        let before = StateManager.shared.currentMode
        Self.performAction(action)
        metadata["mode"] = "\(before.label)→\(StateManager.shared.currentMode.label)"
        DeveloperLogger.shared.log("GlobalTap", "Missed tap fired", metadata: metadata)
    }

#if DEBUG
    /// Feed the judge directly, as the tap thread would.
    func feedForTesting(_ event: GlobalTapJudge.Event) -> GlobalTapJudge.Outcome {
        lock.lock(); defer { lock.unlock() }
        let outcome = judge.feed(event)
        if case .tap(let tap) = outcome { pending.append(tap) }
        return outcome
    }

    func resetForTesting() {
        lock.lock(); judge = GlobalTapJudge(); pending = []; lock.unlock()
    }
#endif
}

private let globalModifierTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo {
        Unmanaged<GlobalModifierWatch>.fromOpaque(userInfo).takeUnretainedValue()
            .receive(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
