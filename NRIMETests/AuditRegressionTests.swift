import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Regression coverage for the 2026-09-13 audit (docs/audit-2026-09-13.md).
/// Each test pins a defect the audit reproduced; they fail until it is fixed.

@MainActor
final class AuditRegressionTests: XCTestCase {
    var controller: NRIMEInputController!
    var client: MockTextInputClient!

    override func setUp() {
        super.setUp()
        StateManager.shared.resetForTesting()
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(.defaultToggleNonEnglish, for: "toggleNonEnglish")
        Settings.shared.setShortcut(.defaultHanjaConvert, for: "hanjaConvert")
        Settings.shared.tapHoldBufferingEnabled = false
        Settings.shared.tapThreshold = 0.2
        Settings.shared.shiftEnterDelay = 0.015
        var config = JapaneseKeyConfig.default
        Settings.shared.japaneseKeyConfig = config
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        (NSApp.delegate as! AppDelegate).candidatePanel = CandidatePanel()
        ChromiumDetector.overrideForTesting = true
        ChromiumDetector.newlineQuirkOverrideForTesting = false
        StateManager.shared.switchTo(.korean)
    }
    override func tearDown() {
        NSApp.candidatePanel?.hide()
        ChromiumDetector.overrideForTesting = nil
        ChromiumDetector.newlineQuirkOverrideForTesting = nil
        controller = nil
        client = nil
        super.tearDown()
    }
    func event(_ key: UInt16, flags: NSEvent.ModifierFlags = [], time: Double = 10,
               type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                        timestamp: time, windowNumber: 0, context: nil, characters: "",
                        charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
    }
    var rightShift: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 4)
    }
    func press(_ key: UInt16, flags: NSEvent.ModifierFlags = [], time: Double = 10,
               type: NSEvent.EventType = .keyDown) {
        _ = controller.handle(event(key, flags: flags, time: time, type: type), client: client)
    }
    func composeGa() { press(0x0F); press(0x28) }
    func tapRightShift() {
        press(0x3C, flags: rightShift, time: 10, type: .flagsChanged)
        press(0x3C, time: 10.08, type: .flagsChanged)
    }
    func settle() {
        let done = expectation(description: "newline delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testNewlineMustNotReplaceTheNextComposition() {
        composeGa()
        press(0x24, flags: rightShift)
        press(0x01) // s -> Korean ㄴ
        press(0x28) // k -> 아: 나
        XCTAssertEqual(client.markedString, "나")
        settle()
        XCTAssertEqual(client.markedString, "나", "Delayed newline must not replace a later preedit")
        XCTAssertTrue(client.composedText.contains("나"))
    }
    func testCandidateShiftEnterMustNotBecomeASoloShiftTap() {
        composeGa()
        NSApp.candidatePanel?.show(candidates: ["家 house"], client: client)
        press(0x3C, flags: rightShift, time: 10, type: .flagsChanged)
        press(0x24, flags: rightShift, time: 10.03)
        press(0x3C, time: 10.05, type: .flagsChanged)
        XCTAssertEqual(StateManager.shared.currentMode, .korean,
                       "The Enter used Shift as a combo, so release must not toggle language")
    }
    func testCandidateShiftEnterMustCompleteTheNewline() {
        composeGa()
        NSApp.candidatePanel?.show(candidates: ["家 house"], client: client)
        press(0x24, flags: rightShift)
        settle()
        XCTAssertEqual(client.insertedTexts, ["家", "\n"])
    }
    func testModeSwitchMustCloseTheKoreanCandidateSession() {
        composeGa()
        NSApp.candidatePanel?.show(candidates: ["家 house"], client: client)
        tapRightShift()
        XCTAssertEqual(StateManager.shared.currentMode, .english)
        XCTAssertFalse(NSApp.candidatePanel!.isVisible(), "Old candidates must not consume English keys")
    }
    func testShiftInsideACommandChordIsNotASoloTap() {
        let handler = ShortcutHandler()
        var actions = 0
        handler.onAction = { _ in actions += 1; return true }
        _ = handler.handleEvent(event(0x37, flags: .command, time: 10, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: rightShift.union(.command), time: 10.01, type: .flagsChanged))
        _ = handler.handleEvent(event(0x3C, flags: .command, time: 10.08, type: .flagsChanged))
        XCTAssertEqual(actions, 0)
    }
    func testModeHotkeyMustNotCommitIntoAuthenticationClient() {
        composeGa()
        let auth = MockTextInputClient()
        auth.bundleID = "com.apple.SecurityAgent"
        controller.testingClientOverride = auth
        _ = controller.handle(event(0x3C, flags: rightShift, time: 10, type: .flagsChanged), client: auth)
        _ = controller.handle(event(0x3C, time: 10.08, type: .flagsChanged), client: auth)
        XCTAssertTrue(auth.insertedTexts.isEmpty, "Mode switching is allowed, but it must not insert old text in an auth client")
    }
    func testSelectedHanjaMouseDismissMustNotLeaveOrphanedMarkedText() {
        client.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        client.setSelectedRange(NSRange(location: 0, length: 1))
        press(0x24, flags: NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20))
        XCTAssertEqual(client.markedString, "한")
        controller.commitOnMouseClickForTesting()
        XCTAssertFalse(NSApp.candidatePanel!.isVisible())
        XCTAssertEqual(client.markedString, "", "Selected original text must be restored/committed before dropping the session")
    }
}
