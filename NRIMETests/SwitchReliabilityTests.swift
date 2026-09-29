import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Language switches that were lost, or fired when nobody asked for them.
/// Stand-in for the window server's hardware keyDown count.
final class FakeKeyDownCounter {
    var value: UInt32 = 0
}

@MainActor
final class SwitchReliabilityTests: XCTestCase {
    var controller: NRIMEInputController!
    var client: MockTextInputClient!
    let hiddenKeys = FakeKeyDownCounter()
    var realKeyDownCount: (() -> UInt32)!

    override func setUp() {
        super.setUp()
        StateManager.shared.resetForTesting()
        // Mirror the real setup: both Shifts are tap keys (isolated test domain).
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(ShortcutConfig(keyCode: 0x38, modifierKeyCode: 0x38, modifiers: 0,
                                                   isModifierOnlyTap: true, label: "Left Shift"),
                                    for: "toggleNonEnglish")
        ShortcutHandler.resetPointerForTesting()
        realKeyDownCount = ShortcutHandler.hardwareKeyDownCount
        let counter = hiddenKeys
        ShortcutHandler.hardwareKeyDownCount = { counter.value }
        Settings.shared.tapHoldBufferingEnabled = false
        Settings.shared.tapThreshold = 0.2
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        StateManager.shared.switchTo(.korean)
    }

    override func tearDown() {
        ShortcutHandler.resetPointerForTesting()
        ShortcutHandler.hardwareKeyDownCount = realKeyDownCount
        controller = nil
        client = nil
        super.tearDown()
    }

    private let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2)
    private let rightShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x4)
    private let bothShifts = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x6)
    private let leftCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x8)
    private let leftOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)

    private func event(_ key: UInt16, flags: NSEvent.ModifierFlags = [], time: Double,
                       type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                         timestamp: time, windowNumber: 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
    }

    /// A handler that records which actions fired, in order.
    private func recordingHandler() -> (ShortcutHandler, () -> [ShortcutHandler.Action]) {
        let handler = ShortcutHandler()
        var fired: [ShortcutHandler.Action] = []
        handler.onAction = { fired.append($0); return true }
        return (handler, { fired })
    }

    private func feed(_ handler: ShortcutHandler, _ key: UInt16, _ flags: NSEvent.ModifierFlags,
                      at time: Double, _ type: NSEvent.EventType = .flagsChanged) {
        _ = handler.handleEvent(event(key, flags: flags, time: time, type: type))
    }

    // MARK: - Test isolation

    func testTestsNeverWriteTheUsersAppGroup() {
        XCTAssertTrue(AppGroupDefaults.isRunningTests,
                      "Test runs must be detected, or every test writes the user's live settings")
        let marker = ShortcutConfig(keyCode: 0x69, modifierKeyCode: 0x69, modifiers: 0,
                                    isModifierOnlyTap: false, label: "F13 isolation marker")
        Settings.shared.setShortcut(marker, for: "switchKorean")
        let testing = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)
        let stored = testing?.data(forKey: "shortcut_switchKorean")
            .flatMap { try? JSONDecoder().decode(ShortcutConfig.self, from: $0) }
        XCTAssertEqual(stored, marker, "Settings must write to the throwaway test domain")
    }

    // MARK: - Secure input

    func testShiftedLetterInAPasswordFieldIsNotASoloShiftTap() {
        let auth = MockTextInputClient()
        auth.bundleID = "com.apple.SecurityAgent"
        controller.testingClientOverride = auth
        _ = controller.handle(event(0x3C, flags: rightShift, time: 10, type: .flagsChanged), client: auth)
        _ = controller.handle(event(0x00, flags: rightShift, time: 10.03), client: auth)
        _ = controller.handle(event(0x3C, time: 10.06, type: .flagsChanged), client: auth)
        XCTAssertEqual(StateManager.shared.currentMode, .korean,
                       "A capital letter typed into a password must not switch the language")
    }

    // MARK: - Tracking that outlives a missed release

    func testTapAfterAReleaseDeliveredElsewhereStillSwitches() {
        let (handler, fired) = recordingHandler()
        // Press seen here; the release went to another controller.
        feed(handler, 0x3C, rightShift, at: 10)
        // Much later, a clean tap on the same key.
        feed(handler, 0x3C, rightShift, at: 20)
        feed(handler, 0x3C, [], at: 20.08)
        XCTAssertEqual(fired(), [.toggleEnglish], "The new press must restart tracking, not extend the stale one")
    }

    func testMissedReleaseOfOneShiftDoesNotTurnTheOthersTapIntoAChord() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x38, leftShift, at: 10)
        // Left Shift's release was never delivered here. Right Shift is tapped
        // alone: the event itself shows only the right-side bit.
        feed(handler, 0x3C, rightShift, at: 20)
        feed(handler, 0x3C, [], at: 20.08)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    func testTappingOneShiftWhileTheOtherIsHeldIsStillAChord() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x38, leftShift, at: 10)
        feed(handler, 0x3C, bothShifts, at: 10.02)
        feed(handler, 0x3C, leftShift, at: 10.08)
        XCTAssertEqual(fired(), [])
    }

    func testOtherShiftLettingGoRightAfterThePressIsRolloverNotAChord() {
        // ㅆ typed with Left Shift, Right Shift tapped to switch before Left is fully up.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x38, leftShift, at: 10)
        feed(handler, 0x11, leftShift, at: 10.05, .keyDown)
        feed(handler, 0x3C, bothShifts, at: 10.10)
        feed(handler, 0x38, rightShift, at: 10.13)
        feed(handler, 0x3C, [], at: 10.18)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    func testOtherShiftHeldWellIntoThePressIsAChord() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x38, leftShift, at: 10)
        feed(handler, 0x11, leftShift, at: 10.05, .keyDown)
        feed(handler, 0x3C, bothShifts, at: 10.10)
        feed(handler, 0x38, rightShift, at: 10.22)
        feed(handler, 0x3C, [], at: 10.25)
        XCTAssertEqual(fired(), [])
    }

    // MARK: - A tap interrupted by the other Shift

    func testTapInterruptedByTheOtherShiftStillSwitches() {
        // Right Shift tapped to switch, Left Shift pressed for a capital I
        // before Right Shift is fully up.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x38, bothShifts, at: 10.08)
        feed(handler, 0x3C, leftShift, at: 10.10)
        feed(handler, 0x22, leftShift, at: 10.12, .keyDown)
        feed(handler, 0x38, [], at: 10.20)
        XCTAssertEqual(fired(), [.toggleEnglish], "Right Shift's tap counts once; Left Shift was for the capital")
    }

    func testFirstPressedCleanShiftWinsWhenBothAreTappedTogether() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x38, bothShifts, at: 10.08)
        feed(handler, 0x3C, leftShift, at: 10.10)
        feed(handler, 0x38, [], at: 10.15)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    func testLetterWhileBothShiftsAreDownSwitchesNeither() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x38, bothShifts, at: 10.08)
        feed(handler, 0x22, bothShifts, at: 10.09, .keyDown)
        feed(handler, 0x3C, leftShift, at: 10.10)
        feed(handler, 0x38, [], at: 10.20)
        XCTAssertEqual(fired(), [])
    }

    func testInterruptedPressHeldPastTheThresholdIsNotATap() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x38, bothShifts, at: 10.25)
        feed(handler, 0x3C, leftShift, at: 10.27)
        feed(handler, 0x38, [], at: 10.40)
        XCTAssertFalse(fired().contains(.toggleEnglish))
    }

    func testReleasingTheLaterShiftFirstIsAChord() {
        // Right held, Left tapped inside it: neither is a solo tap.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x38, bothShifts, at: 10.05)
        feed(handler, 0x38, rightShift, at: 10.10)
        feed(handler, 0x3C, [], at: 10.15)
        XCTAssertEqual(fired(), [])
    }

    func testShiftInterruptedByCommandIsNotATap() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x37, rightShift.union(leftCommand), at: 10.05)
        feed(handler, 0x3C, leftCommand, at: 10.08)
        feed(handler, 0x37, [], at: 10.12)
        XCTAssertEqual(fired(), [])
    }

    // MARK: - Command/Control/Option still coming up

    func testCommandLettingGoRightAfterShiftWentDownIsRollover() {
        // Cmd+V (the V goes to the menu, unseen), then a Right Shift tap while
        // the thumb is still leaving Command.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x37, leftCommand, at: 10)
        hiddenKeys.value += 1 // V
        feed(handler, 0x3C, leftCommand.union(rightShift), at: 10.15)
        feed(handler, 0x37, rightShift, at: 10.17)
        feed(handler, 0x3C, [], at: 10.23)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    func testChordWhoseThirdKeyWentToTheMenuIsNotForgiven() {
        // Cmd+Shift+Z rolled fast: Z never reaches the input method, and
        // Command lets go within the rollover window. That was Redo, not a tap.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x37, leftCommand, at: 10)
        feed(handler, 0x3C, leftCommand.union(rightShift), at: 10.02)
        hiddenKeys.value += 1 // Z, consumed by the menu
        feed(handler, 0x37, rightShift, at: 10.06)
        feed(handler, 0x3C, [], at: 10.11)
        XCTAssertEqual(fired(), [])
    }

    func testCommandHeldWellIntoTheShiftPressIsAChord() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x37, leftCommand, at: 10)
        feed(handler, 0x3C, leftCommand.union(rightShift), at: 10.02)
        feed(handler, 0x37, rightShift, at: 10.10)
        feed(handler, 0x3C, [], at: 10.12)
        XCTAssertEqual(fired(), [])
    }

    func testCommandStillHeldAtShiftReleaseIsAChord() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x37, leftCommand, at: 10)
        feed(handler, 0x3C, leftCommand.union(rightShift), at: 10.02)
        feed(handler, 0x3C, leftCommand, at: 10.08)
        XCTAssertEqual(fired(), [])
    }

    func testOptionRolloverDoesNotForgiveAKeyTypedDuringTheHold() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3A, leftOption, at: 10)
        feed(handler, 0x3C, leftOption.union(rightShift), at: 10.02)
        feed(handler, 0x00, leftOption.union(rightShift), at: 10.03, .keyDown)
        feed(handler, 0x3A, rightShift, at: 10.04)
        feed(handler, 0x3C, [], at: 10.10)
        XCTAssertEqual(fired(), [])
    }

    func testOnlyOneOfTwoHeldModifiersLettingGoQuicklyIsStillAChord() {
        let (handler, fired) = recordingHandler()
        let both = leftCommand.union(leftOption)
        feed(handler, 0x37, leftCommand, at: 10)
        feed(handler, 0x3A, both, at: 10.001)
        feed(handler, 0x3C, both.union(rightShift), at: 10.02)
        feed(handler, 0x37, leftOption.union(rightShift), at: 10.03)
        feed(handler, 0x3A, rightShift, at: 10.12)
        feed(handler, 0x3C, [], at: 10.15)
        XCTAssertEqual(fired(), [])
    }

    // MARK: - Shift+click

    func testShiftClickIsNotATap() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        ShortcutHandler.notePointerDown(timestamp: 10.05, flags: rightShift)
        feed(handler, 0x3C, [], at: 10.10)
        XCTAssertEqual(fired(), [])
    }

    func testLateClickCallbackCannotUndoATapButDoesNotBlockTheNext() {
        // Accepted limit: when the click's callback runs after the release was
        // handled, that tap has already fired. A late click must still not
        // swallow the next tap.
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x3C, [], at: 10.10)
        ShortcutHandler.notePointerDown(timestamp: 10.05, flags: rightShift)
        feed(handler, 0x3C, rightShift, at: 11)
        feed(handler, 0x3C, [], at: 11.08)
        XCTAssertEqual(fired(), [.toggleEnglish, .toggleEnglish])
    }

    func testClickBeforeThePressDoesNotSwallowTheTap() {
        let (handler, fired) = recordingHandler()
        ShortcutHandler.notePointerDown(timestamp: 9.95, flags: rightShift)
        feed(handler, 0x3C, rightShift, at: 10)
        feed(handler, 0x3C, [], at: 10.08)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    func testClickWithTheOtherShiftDoesNotSwallowThisTap() {
        let (handler, fired) = recordingHandler()
        feed(handler, 0x3C, rightShift, at: 10)
        ShortcutHandler.notePointerDown(timestamp: 10.05, flags: leftShift)
        feed(handler, 0x3C, [], at: 10.10)
        XCTAssertEqual(fired(), [.toggleEnglish])
    }

    // MARK: - Client availability

    func testModeSwitchDoesNotDependOnTheControllersClientProxy() {
        // self.client() is nil for this controller; the event still carries one.
        controller.testingClientOverride = nil
        _ = controller.handle(event(0x3C, flags: rightShift, time: 10, type: .flagsChanged), client: client)
        _ = controller.handle(event(0x3C, time: 10.08, type: .flagsChanged), client: client)
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    // MARK: - Authentication UI step-aside

    func testAbandonedClaimSurvivesReadingsThatSayNothingAboutIt() {
        let p: pid_t = 101, q: pid_t = 202
        // Flag still on, holder unknown or another app: keep the latch.
        XCTAssertEqual(InputSourceRecovery.nextAbandonedClaim(previous: p, flagActive: true, authHolder: nil), p)
        XCTAssertEqual(InputSourceRecovery.nextAbandonedClaim(previous: p, flagActive: true, authHolder: p), p)
        // Secure input fully off, or a different authentication process: release.
        XCTAssertNil(InputSourceRecovery.nextAbandonedClaim(previous: p, flagActive: false, authHolder: nil))
        XCTAssertNil(InputSourceRecovery.nextAbandonedClaim(previous: p, flagActive: true, authHolder: q))
        XCTAssertNil(InputSourceRecovery.nextAbandonedClaim(previous: nil, flagActive: true, authHolder: p))
    }

    func testStepAsideStaysOffAcrossAnUnknownReadingOfTheSameClaim() {
        let p: pid_t = 101
        let nrime = "com.nrime.inputmethod.app.en"
        var latch: pid_t? = p
        for reading: pid_t? in [nil, p] {
            latch = InputSourceRecovery.nextAbandonedClaim(previous: latch, flagActive: true, authHolder: reading)
            XCTAssertEqual(
                InputSourceRecovery.secureInputAction(
                    fallbackEnabled: true, heldByAuthenticationUI: reading != nil,
                    claimAbandoned: reading != nil && reading == latch,
                    currentSourceID: nrime, rememberedSourceID: nil, secondsSinceSteppedAside: nil),
                .none)
        }
    }

    func testRestoreOnAnUnknownReadingKeepsTheClaimItSteppedAsideFor() {
        let p: pid_t = 101, q: pid_t = 202
        XCTAssertEqual(InputSourceRecovery.latchAfterRestore(flagActive: true, holder: nil, steppedAsideFor: p), p)
        XCTAssertEqual(InputSourceRecovery.latchAfterRestore(flagActive: true, holder: q, steppedAsideFor: p), q)
        XCTAssertNil(InputSourceRecovery.latchAfterRestore(flagActive: false, holder: nil, steppedAsideFor: p))

        // Stepped aside for P, one unknown reading brings us back, P reappears:
        // no fresh 20 seconds.
        let nrime = "com.nrime.inputmethod.app.en"
        let latch = InputSourceRecovery.latchAfterRestore(flagActive: true, holder: nil, steppedAsideFor: p)
        let next = InputSourceRecovery.nextAbandonedClaim(previous: latch, flagActive: true, authHolder: p)
        XCTAssertEqual(
            InputSourceRecovery.secureInputAction(
                fallbackEnabled: true, heldByAuthenticationUI: true, claimAbandoned: next == p,
                currentSourceID: nrime, rememberedSourceID: nil, secondsSinceSteppedAside: nil),
            .none)
    }

    // MARK: - Developer log redaction

    private func logLines() throws -> [Substring] {
        DeveloperLogger.shared.drainForTesting()
        let url = DeveloperLogLocation.fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    }

    private func withDeveloperLog(_ body: () throws -> Void) rethrows {
        Settings.shared.developerModeEnabled = true
        try? FileManager.default.removeItem(at: DeveloperLogLocation.directoryURL())
        defer {
            Settings.shared.developerModeEnabled = false
            try? FileManager.default.removeItem(at: DeveloperLogLocation.directoryURL())
        }
        try body()
    }

    func testShiftInsideAPasswordLeavesNoTimingInTheLog() throws {
        try withDeveloperLog {
            let (handler, fired) = recordingHandler()
            handler.isSensitiveContext = { true }
            feed(handler, 0x38, leftShift, at: 10)
            handler.observeConsumedKeyDown(event(0x00, flags: leftShift, time: 10.03))
            feed(handler, 0x38, [], at: 10.08)
            // A switch that fires in a password field is still worth knowing about.
            feed(handler, 0x3C, rightShift, at: 11)
            feed(handler, 0x3C, [], at: 11.08)
            XCTAssertEqual(fired(), [.toggleEnglish])

            let tapLines = try logLines().filter { $0.contains("[Tap]") }
            XCTAssertEqual(tapLines.count, 1, "Only the fired switch is logged")
            XCTAssertTrue(tapLines.allSatisfy { $0.contains("outcome=fired") && $0.contains("secure=Y") })
            XCTAssertFalse(tapLines.contains { $0.contains("elapsedMs") || $0.contains("overlapMs") })
        }
    }

    func testTapLinesNameTheControllerAndTheDecision() throws {
        try withDeveloperLog {
            let (handler, _) = recordingHandler()
            handler.isSensitiveContext = { false }
            feed(handler, 0x3C, rightShift, at: 10)
            feed(handler, 0x00, rightShift, at: 10.03, .keyDown)
            feed(handler, 0x3C, [], at: 10.08)
            let line = try XCTUnwrap(logLines().first { $0.contains("[Tap]") })
            XCTAssertTrue(line.contains("outcome=combo"))
            XCTAssertTrue(line.contains("reason=keyDown"))
            XCTAssertTrue(line.contains("ctl=\(handler.diagID)"))
        }
    }

    func testLateClickForAFiredTapIsLogged() throws {
        try withDeveloperLog {
            let (handler, fired) = recordingHandler()
            handler.isSensitiveContext = { false }
            feed(handler, 0x3C, rightShift, at: 10)
            feed(handler, 0x3C, [], at: 10.10)
            ShortcutHandler.notePointerDown(timestamp: 10.05, flags: rightShift)
            XCTAssertEqual(fired(), [.toggleEnglish])
            XCTAssertTrue(try logLines().contains { $0.contains("Late pointer") })
        }
    }

    func testStepAsideDoesNotRestartForAClaimTheCapAlreadyGaveUpOn() {
        let nrime = "com.nrime.inputmethod.app.en"
        XCTAssertEqual(
            InputSourceRecovery.secureInputAction(
                fallbackEnabled: true, heldByAuthenticationUI: true, claimAbandoned: true,
                currentSourceID: nrime, rememberedSourceID: nil, secondsSinceSteppedAside: nil),
            .none)
        XCTAssertEqual(
            InputSourceRecovery.secureInputAction(
                fallbackEnabled: true, heldByAuthenticationUI: true, claimAbandoned: false,
                currentSourceID: nrime, rememberedSourceID: nil, secondsSinceSteppedAside: nil),
            .switchToASCII(remembering: nrime))
    }
}
