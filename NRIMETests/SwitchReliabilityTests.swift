import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Language switches that were lost, or fired when nobody asked for them.
@MainActor
final class SwitchReliabilityTests: XCTestCase {
    var controller: NRIMEInputController!
    var client: MockTextInputClient!

    override func setUp() {
        super.setUp()
        StateManager.shared.resetForTesting()
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(.defaultToggleNonEnglish, for: "toggleNonEnglish")
        Settings.shared.tapHoldBufferingEnabled = false
        Settings.shared.tapThreshold = 0.2
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        StateManager.shared.switchTo(.korean)
    }

    override func tearDown() {
        controller = nil
        client = nil
        super.tearDown()
    }

    private let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2)
    private let rightShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x4)
    private let bothShifts = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x6)

    private func event(_ key: UInt16, flags: NSEvent.ModifierFlags = [], time: Double,
                       type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                         timestamp: time, windowNumber: 0, context: nil, characters: "",
                         charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
    }

    private func countingHandler() -> (ShortcutHandler, () -> Int) {
        let handler = ShortcutHandler()
        var fired = 0
        handler.onAction = { _ in fired += 1; return true }
        return (handler, { fired })
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
        let (handler, fired) = countingHandler()
        // Press seen here; the release went to another controller.
        _ = handler.handleEvent(event(0x3C, flags: rightShift, time: 10, type: .flagsChanged))
        // Much later, a clean tap on the same key.
        _ = handler.handleEvent(event(0x3C, flags: rightShift, time: 20, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, time: 20.08, type: .flagsChanged))
        XCTAssertEqual(fired(), 1, "The new press must restart tracking, not extend the stale one")
    }

    func testMissedReleaseOfOneShiftDoesNotTurnTheOthersTapIntoAChord() {
        let (handler, fired) = countingHandler()
        _ = handler.handleEvent(event(0x38, flags: leftShift, time: 10, type: .flagsChanged))
        // Left Shift's release was never delivered here. Right Shift is tapped
        // alone: the event itself shows only the right-side bit.
        _ = handler.handleEvent(event(0x3C, flags: rightShift, time: 20, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, time: 20.08, type: .flagsChanged))
        XCTAssertEqual(fired(), 1)
    }

    func testTappingOneShiftWhileTheOtherIsHeldIsStillAChord() {
        let (handler, fired) = countingHandler()
        _ = handler.handleEvent(event(0x38, flags: leftShift, time: 10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: bothShifts, time: 10.02, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: leftShift, time: 10.08, type: .flagsChanged))
        XCTAssertEqual(fired(), 0)
    }

    func testOtherShiftLettingGoRightAfterThePressIsRolloverNotAChord() {
        // ㅆ typed with Left Shift, Right Shift tapped to switch before Left is fully up.
        let (handler, fired) = countingHandler()
        _ = handler.handleEvent(event(0x38, flags: leftShift, time: 10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: bothShifts, time: 10.10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x38, flags: rightShift, time: 10.13, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, time: 10.18, type: .flagsChanged))
        XCTAssertEqual(fired(), 1)
    }

    func testOtherShiftHeldWellIntoThePressIsAChord() {
        let (handler, fired) = countingHandler()
        _ = handler.handleEvent(event(0x38, flags: leftShift, time: 10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: bothShifts, time: 10.10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x38, flags: rightShift, time: 10.22, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, time: 10.25, type: .flagsChanged))
        XCTAssertEqual(fired(), 0)
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
