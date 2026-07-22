import Cocoa
import XCTest
@testable import NRIME

/// Design-B tap-hold buffering: a letter arriving while a tap-registered
/// modifier is briefly held is buffered; the modifier's release timing decides
/// tap-rollover (switch + unshifted replay) vs deliberate shifted letter.
/// Traces follow the design document (T1/T2/T3/T5/T8 + guards).
final class TapHoldBufferingTests: XCTestCase {

    private var handler: ShortcutHandler!
    private var firedActions: [ShortcutHandler.Action] = []
    private var replays: [(keyCode: UInt16, keepShift: Bool)] = []

    private var originalEnabled: Bool = false
    private var originalWindow: TimeInterval = 0.05
    private var originalThreshold: TimeInterval = 0.2
    private var originalShortcuts: [String: ShortcutConfig] = [:]

    private let rightShift = ShortcutConfig.keyCodeRightShift // 0x3C
    private let leftShift = ShortcutConfig.keyCodeLeftShift   // 0x38
    private let keyA: UInt16 = 0x00
    private let keyB: UInt16 = 0x0B

    override func setUp() {
        super.setUp()
        originalEnabled = Settings.shared.tapHoldBufferingEnabled
        originalWindow = Settings.shared.tapOverlapWindow
        originalThreshold = Settings.shared.tapThreshold
        for key in ["toggleEnglish", "toggleNonEnglish", "switchKorean", "switchJapanese", "hanjaConvert"] {
            originalShortcuts[key] = Settings.shared.shortcut(for: key)
        }
        Settings.shared.tapHoldBufferingEnabled = true
        Settings.shared.tapOverlapWindow = 0.05
        Settings.shared.tapThreshold = 0.2
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")     // RS tap
        Settings.shared.setShortcut(.defaultToggleNonEnglish, for: "toggleNonEnglish") // Shift+Space combo
        var disabledKorean = ShortcutConfig.defaultSwitchKorean
        disabledKorean.disabled = true
        Settings.shared.setShortcut(disabledKorean, for: "switchKorean")
        var disabledJapanese = ShortcutConfig.defaultSwitchJapanese
        disabledJapanese.disabled = true
        Settings.shared.setShortcut(disabledJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(.defaultHanjaConvert, for: "hanjaConvert")

        handler = ShortcutHandler()
        firedActions = []
        replays = []
        handler.onAction = { [weak self] action in
            self?.firedActions.append(action)
            return true
        }
        handler.onReplay = { [weak self] event, keepShift in
            self?.replays.append((event.keyCode, keepShift))
        }
    }

    override func tearDown() {
        Settings.shared.tapHoldBufferingEnabled = originalEnabled
        Settings.shared.tapOverlapWindow = originalWindow
        Settings.shared.tapThreshold = originalThreshold
        for (key, config) in originalShortcuts {
            Settings.shared.setShortcut(config, for: key)
        }
        handler = nil
        super.tearDown()
    }

    // T1: RS↓(t0) a↓(+40ms) RS↑(+70ms) — rollover after an intended tap.
    func testTapRolloverSwitchesModeAndReplaysUnshifted() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))

        let consumed = handler.handleEvent(letterDown(keyA, side: .right, at: 0.040))
        XCTAssertTrue(consumed, "Ambiguous letter must be buffered, not passed to the engine")
        XCTAssertTrue(handler.hasPendingLetterForTesting)
        XCTAssertTrue(replays.isEmpty, "No replay before the release settles intent")

        let releaseConsumed = handler.handleEvent(shiftUp(rightShift, at: 0.070))
        XCTAssertTrue(releaseConsumed)
        XCTAssertEqual(firedActions, [.toggleEnglish], "Short overlap = tap: mode switch fires")
        XCTAssertEqual(replays.count, 1)
        XCTAssertEqual(replays[0].keyCode, keyA)
        XCTAssertFalse(replays[0].keepShift, "Tap rollover replays the letter unshifted")
    }

    // T2: LS↓(t0) a↓(+50ms) … LS↑(+180ms) — deliberate shifted letter.
    func testLongOverlapReleaseSettlesAsShiftedHold() {
        // Mirror the user's real setup: Left Shift tap toggles Korean/Japanese
        Settings.shared.setShortcut(
            ShortcutConfig(keyCode: leftShift, modifierKeyCode: leftShift,
                           modifiers: 0, isModifierOnlyTap: true, label: "Left Shift"),
            for: "toggleNonEnglish")

        _ = handler.handleEvent(shiftDown(leftShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .left, at: 0.050)))

        _ = handler.handleEvent(shiftUp(leftShift, at: 0.180))
        XCTAssertTrue(firedActions.isEmpty, "Long overlap = deliberate capital: no mode switch")
        XCTAssertEqual(replays.count, 1)
        XCTAssertTrue(replays[0].keepShift, "Letter replays with Shift intact")
    }

    // T2 variant: the overlap-window timer fires before the release.
    func testTimerTimeoutSettlesAsShiftedHoldAndSuppressesLaterTap() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .right, at: 0.030)))

        handler.flushPendingForTesting() // overlap window elapsed

        XCTAssertEqual(replays.count, 1)
        XCTAssertTrue(replays[0].keepShift)

        _ = handler.handleEvent(shiftUp(rightShift, at: 0.150))
        XCTAssertTrue(firedActions.isEmpty, "The hold consumed the gesture — release must not fire the tap")
    }

    // T3: letter arriving after tapThreshold — not ambiguous, no buffering.
    func testLetterAfterTapThresholdIsNotBuffered() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))

        let consumed = handler.handleEvent(letterDown(keyA, side: .right, at: 0.300))
        XCTAssertFalse(consumed, "Past the tap threshold the letter takes the normal path")
        XCTAssertFalse(handler.hasPendingLetterForTesting)
        XCTAssertTrue(replays.isEmpty)
    }

    // T5: LS↓ a↓ b↓ — a second key is unambiguous combo evidence.
    func testSecondKeySettlesFirstAsHoldImmediately() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .right, at: 0.020)))

        let secondConsumed = handler.handleEvent(letterDown(keyB, side: .right, at: 0.040))
        XCTAssertEqual(replays.count, 1, "First letter settles as hold when the second arrives")
        XCTAssertEqual(replays[0].keyCode, keyA)
        XCTAssertTrue(replays[0].keepShift)
        XCTAssertFalse(secondConsumed, "Second letter takes the normal shifted path")
        XCTAssertFalse(handler.hasPendingLetterForTesting, "Second letter is not re-buffered")
    }

    // T8: key repeats are never buffered.
    func testKeyRepeatIsNotBuffered() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .right, at: 0.020)))

        let repeatConsumed = handler.handleEvent(
            letterDown(keyA, side: .right, at: 0.045, isARepeat: true))
        XCTAssertEqual(replays.count, 1, "Repeat flushes the pending letter as hold")
        XCTAssertTrue(replays[0].keepShift)
        XCTAssertFalse(repeatConsumed)
    }

    // Guard: feature defaults to OFF — behavior is byte-for-byte the old path.
    func testDisabledFeatureNeverBuffers() {
        Settings.shared.tapHoldBufferingEnabled = false
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))

        let consumed = handler.handleEvent(letterDown(keyA, side: .right, at: 0.040))
        XCTAssertFalse(consumed)
        XCTAssertFalse(handler.hasPendingLetterForTesting)

        _ = handler.handleEvent(shiftUp(rightShift, at: 0.070))
        XCTAssertTrue(firedActions.isEmpty, "Combo-marked release does not fire the tap (old behavior)")
    }

    // Guard: a modifier that also drives an enabled combo shortcut never buffers.
    func testComboRegisteredModifierIsExcluded() {
        var combo = ShortcutConfig.defaultSwitchKorean // Right Shift + 1
        combo.disabled = false
        Settings.shared.setShortcut(combo, for: "switchKorean")

        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        let consumed = handler.handleEvent(letterDown(keyA, side: .right, at: 0.040))
        XCTAssertFalse(consumed, "Combo users expect combo semantics — no buffering")
        XCTAssertFalse(handler.hasPendingLetterForTesting)
    }

    // Guard: both physical shifts down is not a tap gesture.
    func testBothShiftSidesDownIsNotBuffered() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        let consumed = handler.handleEvent(letterDown(keyA, side: .both, at: 0.040))
        XCTAssertFalse(consumed)
        XCTAssertFalse(handler.hasPendingLetterForTesting)
    }

    // Guard: digits/symbols keep their shifted meanings — letters only.
    func testDigitsAreNotBuffered() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        let consumed = handler.handleEvent(
            keyEvent(keyCode: 0x12, characters: "!", flags: shiftFlags(side: .right), at: 0.040))
        XCTAssertFalse(consumed)
        XCTAssertFalse(handler.hasPendingLetterForTesting)
    }

    // Stuck-state: the modifier flag vanished (missed release) — next keyDown flushes.
    func testMissedReleaseFlushesOnNextKeyDown() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .right, at: 0.020)))

        // Release event lost (focus change) — a later shift-less keyDown arrives
        _ = handler.handleEvent(keyEvent(keyCode: keyB, characters: "b", flags: [], at: 1.0))
        XCTAssertEqual(replays.count, 1, "Pending letter must not be lost")
        XCTAssertTrue(replays[0].keepShift)
        XCTAssertFalse(handler.hasPendingLetterForTesting)
    }

    // reset() drops the buffer without replaying into a dead client.
    func testResetDropsPendingWithoutReplay() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        XCTAssertTrue(handler.handleEvent(letterDown(keyA, side: .right, at: 0.020)))

        handler.reset()
        XCTAssertFalse(handler.hasPendingLetterForTesting)
        XCTAssertTrue(replays.isEmpty)
    }

    // Pure tap with no letter is unaffected (T4).
    func testPureTapStillFires() {
        _ = handler.handleEvent(shiftDown(rightShift, at: 0))
        let consumed = handler.handleEvent(shiftUp(rightShift, at: 0.080))
        XCTAssertTrue(consumed)
        XCTAssertEqual(firedActions, [.toggleEnglish])
        XCTAssertTrue(replays.isEmpty)
    }

    // MARK: - Event helpers

    private enum ShiftSide { case left, right, both }

    private func shiftFlags(side: ShiftSide) -> NSEvent.ModifierFlags {
        let device: UInt
        switch side {
        case .left:  device = 0x0000_0002
        case .right: device = 0x0000_0004
        case .both:  device = 0x0000_0006
        }
        return NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | device)
    }

    private func shiftDown(_ keyCode: UInt16, at timestamp: TimeInterval) -> NSEvent {
        flagsChangedEvent(keyCode: keyCode,
                          flags: shiftFlags(side: keyCode == leftShift ? .left : .right),
                          at: timestamp)
    }

    private func shiftUp(_ keyCode: UInt16, at timestamp: TimeInterval) -> NSEvent {
        flagsChangedEvent(keyCode: keyCode, flags: [], at: timestamp)
    }

    private func letterDown(_ keyCode: UInt16, side: ShiftSide,
                            at timestamp: TimeInterval, isARepeat: Bool = false) -> NSEvent {
        keyEvent(keyCode: keyCode, characters: "a",
                 flags: shiftFlags(side: side), at: timestamp, isARepeat: isARepeat)
    }

    private func keyEvent(keyCode: UInt16, characters: String,
                          flags: NSEvent.ModifierFlags,
                          at timestamp: TimeInterval, isARepeat: Bool = false) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: timestamp, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: isARepeat, keyCode: keyCode
        ) else {
            XCTFail("Failed to create key event")
            fatalError()
        }
        return event
    }

    private func flagsChangedEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                                   at timestamp: TimeInterval) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: flags,
            timestamp: timestamp, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        ) else {
            XCTFail("Failed to create flagsChanged event")
            fatalError()
        }
        return event
    }
}
