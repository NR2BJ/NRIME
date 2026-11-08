import Cocoa
import XCTest
@testable import NRIME

/// The system-wide modifier watch (GlobalModifierWatch): which gestures are
/// clean taps, and when a tap the input method's own path missed is switched.
/// No event tap is created in tests; events are fed in directly.
@MainActor
final class GlobalModifierWatchTests: XCTestCase {
    private let rightShiftDown: UInt64 = 0x20004
    private let leftShiftDown: UInt64 = 0x20002
    private let leftCommandDown: UInt64 = 0x100008
    private var fired: [ShortcutHandler.Action] = []
    private var originalPerform: ((ShortcutHandler.Action) -> Void)!
    private var originalShortcuts: [String: ShortcutConfig] = [:]
    private var originalThreshold: TimeInterval = 0.2

    override func setUp() {
        super.setUp()
        for name in ["toggleEnglish", "toggleNonEnglish"] {
            originalShortcuts[name] = Settings.shared.shortcut(for: name)
        }
        originalThreshold = Settings.shared.tapThreshold
        StateManager.shared.resetForTesting()
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish") // Right Shift tap
        Settings.shared.setShortcut(ShortcutConfig(keyCode: 0x38, modifierKeyCode: 0x38, modifiers: 0,
                                                   isModifierOnlyTap: true, label: "Left Shift"),
                                    for: "toggleNonEnglish")
        Settings.shared.tapThreshold = 0.2
        Settings.shared.tapHoldBufferingEnabled = false
        TapReleaseLedger.resetForTesting()
        GlobalModifierWatch.shared.resetForTesting()
        InputSourceSelector.currentSourceIDForTesting = InputSourceSelector.visibleInputSourceID
        originalPerform = GlobalModifierWatch.performAction
        fired = []
        GlobalModifierWatch.performAction = { [unowned self] action in fired.append(action) }
        ShortcutHandler.resetPointerForTesting()
    }

    override func tearDown() {
        GlobalModifierWatch.performAction = originalPerform
        GlobalModifierWatch.shared.resetForTesting()
        TapReleaseLedger.resetForTesting()
        InputSourceSelector.currentSourceIDForTesting = nil
        StateManager.shared.resetForTesting()
        for (name, config) in originalShortcuts { Settings.shared.setShortcut(config, for: name) }
        Settings.shared.tapThreshold = originalThreshold
        super.tearDown()
    }

    private func flags(_ key: UInt16, _ flags: UInt64, at time: TimeInterval) -> GlobalTapJudge.Event {
        GlobalTapJudge.Event(kind: .flags, keyCode: key, flags: flags, timestamp: time)
    }

    private func key(at time: TimeInterval) -> GlobalTapJudge.Event {
        GlobalTapJudge.Event(kind: .keyDown, keyCode: 0x00, flags: 0, timestamp: time)
    }

    // MARK: - Judge

    func testCleanTapIsFound() {
        var judge = GlobalTapJudge()
        XCTAssertEqual(judge.feed(flags(0x3C, rightShiftDown, at: 10.0)), .none)
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 10.09)),
                       .tap(.init(keyCode: 0x3C, down: 10.0, release: 10.09)))
    }

    func testKeyOrClickDuringThePressIsNoTap() {
        var judge = GlobalTapJudge()
        _ = judge.feed(flags(0x3C, rightShiftDown, at: 10.0))
        _ = judge.feed(key(at: 10.03))
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 10.09)), .none, "Shift+letter")

        _ = judge.feed(flags(0x3C, rightShiftDown, at: 11.0))
        _ = judge.feed(GlobalTapJudge.Event(kind: .pointer, keyCode: 0, flags: rightShiftDown, timestamp: 11.03))
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 11.09)), .none, "Shift+click")
    }

    func testChordIsNoTap() {
        var judge = GlobalTapJudge()
        _ = judge.feed(flags(0x37, leftCommandDown, at: 10.0))
        _ = judge.feed(flags(0x3C, leftCommandDown | rightShiftDown, at: 10.05))
        XCTAssertEqual(judge.feed(flags(0x3C, leftCommandDown, at: 10.1)), .none, "Command was held")
    }

    /// Each modifier change delivered twice, 5–20 ms apart: one gesture.
    func testRepeatedEventsAreOneGesture() {
        var judge = GlobalTapJudge()
        _ = judge.feed(flags(0x3C, rightShiftDown, at: 10.0))
        guard case .repeated(let keyCode, let gap) = judge.feed(flags(0x3C, rightShiftDown, at: 10.006)) else {
            return XCTFail("The second press is a repeat")
        }
        XCTAssertEqual(keyCode, 0x3C)
        XCTAssertEqual(gap, 0.006, accuracy: 0.0001)
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 10.09)),
                       .tap(.init(keyCode: 0x3C, down: 10.0, release: 10.09)), "Timed from the first press")
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 10.1)), .none, "The repeated release is nothing")
    }

    /// A press whose release never arrived does not block the next one.
    func testLostReleaseDoesNotStickTheKey() {
        var judge = GlobalTapJudge()
        _ = judge.feed(flags(0x3C, rightShiftDown, at: 10.0))
        _ = judge.feed(flags(0x3C, rightShiftDown, at: 12.0))
        XCTAssertEqual(judge.feed(flags(0x3C, 0, at: 12.08)),
                       .tap(.init(keyCode: 0x3C, down: 12.0, release: 12.08)))
    }

    // MARK: - Deciding

    private func feedTap(_ key: UInt16, down: TimeInterval, release: TimeInterval) {
        let side: UInt64 = key == 0x3C ? rightShiftDown : leftShiftDown
        _ = GlobalModifierWatch.shared.feedForTesting(flags(key, side, at: down))
        _ = GlobalModifierWatch.shared.feedForTesting(flags(key, 0, at: release))
    }

    /// The usual case: the input method had the release; the watch stays out.
    func testTapTheInputMethodSawIsLeftAlone() {
        feedTap(0x3C, down: 10.0, release: 10.09)
        TapReleaseLedger.noteIMKRelease(keyCode: 0x3C, timestamp: 10.09, tracked: true)

        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 10.5)

        XCTAssertEqual(fired, [])
    }

    /// No text field active: the input method never heard of the tap.
    func testMissedTapSwitches() {
        feedTap(0x3C, down: 10.0, release: 10.09)

        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 10.5)

        XCTAssertEqual(fired, [.toggleEnglish])
        XCTAssertTrue(TapReleaseLedger.firedGlobally(keyCode: 0x3C, near: 10.09))
    }

    func testMissedTapWaitsForTheGracePeriod() {
        feedTap(0x38, down: 10.0, release: 10.09)

        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 10.12)
        XCTAssertEqual(fired, [], "The input method's path may still report it")

        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 10.2)
        XCTAssertEqual(fired, [.toggleNonEnglish])
    }

    /// The next key reaching the input method settles a missed tap at once,
    /// so the letter goes to the new mode.
    func testNextKeySettlesAMissedTapFirst() {
        feedTap(0x3C, down: 10.0, release: 10.09)

        GlobalModifierWatch.shared.resolve(before: 10.11, excludingKey: nil, via: "nextKey", now: 10.11)

        XCTAssertEqual(fired, [.toggleEnglish])
    }

    /// The release itself reaching the input method is not "the next key".
    func testTheReleaseItselfDoesNotSettleItsOwnTap() {
        feedTap(0x3C, down: 10.0, release: 10.09)

        GlobalModifierWatch.shared.resolve(before: 10.09 + 0.000_001, excludingKey: 0x3C, via: "nextKey", now: 10.09)

        XCTAssertEqual(fired, [])
    }

    /// If the two clocks ever disagreed, timestamps would stop matching; a
    /// release the input method decided a moment ago still keeps the watch out.
    func testRecentDecisionByTheInputMethodBlocksEvenWithoutAMatch() {
        TapReleaseLedger.noteIMKRelease(keyCode: 0x3C, timestamp: 99.0, tracked: true)
        feedTap(0x3C, down: 10.0, release: 10.09)

        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 10.5)

        XCTAssertEqual(fired, [])
    }

    func testTooLongOrAnotherInputSourceDoesNotSwitch() {
        feedTap(0x3C, down: 10.0, release: 10.35)
        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 11)
        XCTAssertEqual(fired, [], "Held past the tap threshold")

        InputSourceSelector.currentSourceIDForTesting = "com.apple.keylayout.ABC"
        feedTap(0x3C, down: 12.0, release: 12.08)
        GlobalModifierWatch.shared.resolve(before: nil, excludingKey: nil, via: "wait", now: 13)
        XCTAssertEqual(fired, [], "NRIME is not the input source")
    }

    /// The input method's path reached by a release the watch already
    /// switched for (late, after a stall) must not switch again.
    func testInputMethodSkipsAReleaseTheWatchAlreadyFired() {
        let handler = ShortcutHandler()
        var actions: [ShortcutHandler.Action] = []
        handler.onAction = { actions.append($0); return true }
        TapReleaseLedger.noteGlobalFire(keyCode: 0x3C, timestamp: 10.09)

        _ = handler.handleEvent(nsFlags(0x3C, rightShiftDown, at: 10.0))
        _ = handler.handleEvent(nsFlags(0x3C, 0, at: 10.09))
        XCTAssertEqual(actions, [], "Switched once, by the watch")

        _ = handler.handleEvent(nsFlags(0x3C, rightShiftDown, at: 11.0))
        _ = handler.handleEvent(nsFlags(0x3C, 0, at: 11.09))
        XCTAssertEqual(actions, [.toggleEnglish], "Later taps are the input method's again")
        XCTAssertTrue(TapReleaseLedger.decidedByIMK(keyCode: 0x3C, near: 11.09))
    }

    private func nsFlags(_ key: UInt16, _ flags: UInt64, at time: TimeInterval) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero,
                         modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                         timestamp: time, windowNumber: 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
    }

    // MARK: - Clock

    /// CGEvent timestamps may be nanoseconds or machine ticks; the one that
    /// lands near "now" is taken.
    func testEventTimestampUnitIsChosenByWhichLandsNearNow() {
        let appleSilicon = mach_timebase_info_data_t(numer: 125, denom: 3)
        let now: TimeInterval = 80_000.0
        let asNanoseconds = CGEventTimestamp((now - 0.002) * 1e9)
        let asTicks = CGEventTimestamp((now - 0.002) * 1e9 * 3 / 125)
        XCTAssertEqual(GlobalModifierWatch.seconds(fromEventTimestamp: asNanoseconds, now: now,
                                                   timebase: appleSilicon), now - 0.002, accuracy: 0.0001)
        XCTAssertEqual(GlobalModifierWatch.seconds(fromEventTimestamp: asTicks, now: now,
                                                   timebase: appleSilicon), now - 0.002, accuracy: 0.0001)
    }
}
