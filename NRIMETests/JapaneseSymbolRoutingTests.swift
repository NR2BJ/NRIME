import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Covers symbol keys as they arrive through the controller, where shortcut
/// matching runs before the engine ever sees the event.
@MainActor
final class JapaneseSymbolRoutingTests: XCTestCase {

    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!
    private var originalToggleEnglish: ShortcutConfig!
    private var originalToggleNonEnglish: ShortcutConfig!
    private var originalSwitchKorean: ShortcutConfig!
    private var originalSwitchJapanese: ShortcutConfig!
    private var originalHanjaConvert: ShortcutConfig!
    private var originalJapaneseConfig: JapaneseKeyConfig!

    override func setUp() {
        super.setUp()
        originalToggleEnglish = Settings.shared.shortcut(for: "toggleEnglish")
        originalToggleNonEnglish = Settings.shared.shortcut(for: "toggleNonEnglish")
        originalSwitchKorean = Settings.shared.shortcut(for: "switchKorean")
        originalSwitchJapanese = Settings.shared.shortcut(for: "switchJapanese")
        originalHanjaConvert = Settings.shared.shortcut(for: "hanjaConvert")
        originalJapaneseConfig = Settings.shared.japaneseKeyConfig

        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(.defaultToggleNonEnglish, for: "toggleNonEnglish")
        Settings.shared.setShortcut(.defaultSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(.defaultSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(.defaultHanjaConvert, for: "hanjaConvert")

        var config = JapaneseKeyConfig.default
        config.prediction = false        // no Mozc IPC in unit tests
        config.liveConversion = false
        Settings.shared.japaneseKeyConfig = config

        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        StateManager.shared.switchTo(.japanese)
    }

    override func tearDown() {
        StateManager.shared.switchTo(.english)
        Settings.shared.setShortcut(originalToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(originalToggleNonEnglish, for: "toggleNonEnglish")
        Settings.shared.setShortcut(originalSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(originalSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(originalHanjaConvert, for: "hanjaConvert")
        Settings.shared.japaneseKeyConfig = originalJapaneseConfig
        controller = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Question mark (no shortcut binding on this key)

    func testShiftSlashInsertsFullWidthQuestionMark() {
        let handled = controller.handle(
            keyEvent(keyCode: 0x2C, characters: "?", modifiers: [.shift]), client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["？"])
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    // MARK: - Exclamation mark (collides with the Right Shift + 1 shortcut)

    func testLeftShiftOneInsertsFullWidthExclamation() {
        // Right Shift + 1 is the mode-switch shortcut, so the left key must stay
        // available for typing ！.
        pressModifier(keyCode: ShortcutConfig.keyCodeLeftShift)

        let handled = controller.handle(
            keyEvent(keyCode: 0x12, characters: "!", modifiers: [.shift]), client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["！"])
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    func testRightShiftOneStillSwitchesToKorean() {
        pressModifier(keyCode: ShortcutConfig.keyCodeRightShift)

        let handled = controller.handle(
            keyEvent(keyCode: 0x12, characters: "!", modifiers: [.shift]), client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, [])
        XCTAssertEqual(StateManager.shared.currentMode, .korean,
                       "Right Shift + 1 is the configured mode-switch shortcut")
    }

    /// The real-world case: no flagsChanged reached the IME (focus changed while
    /// the key was held, or a previous combo cleared the tracking), so the
    /// handler cannot tell which Shift is down.
    func testShiftOneWithUntrackedModifierDoesNotHijackTyping() {
        let handled = controller.handle(
            keyEvent(keyCode: 0x12, characters: "!", modifiers: [.shift]), client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["！"],
                       "An untracked Shift must not be assumed to be the shortcut's side")
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    // MARK: - Device-dependent modifier bits (what real keyDown events carry)

    func testDeviceBitsIdentifyLeftShiftWithoutPriorTracking() {
        // No flagsChanged at all — the side comes from the event's own bits.
        let handled = controller.handle(
            keyEvent(keyCode: 0x12, characters: "!", modifiers: shiftFlags(side: .left)),
            client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["！"])
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    func testDeviceBitsIdentifyRightShiftWithoutPriorTracking() {
        let handled = controller.handle(
            keyEvent(keyCode: 0x12, characters: "!", modifiers: shiftFlags(side: .right)),
            client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, [])
        XCTAssertEqual(StateManager.shared.currentMode, .korean)
    }

    private enum ShiftSide { case left, right }

    /// Shift flags as macOS delivers them: the device-independent bit plus the
    /// device-dependent bit naming which physical key is down.
    private func shiftFlags(side: ShiftSide) -> NSEvent.ModifierFlags {
        let deviceBit: UInt = (side == .left) ? 0x0000_0002 : 0x0000_0004
        return NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.shift.rawValue | deviceBit)
    }

    // MARK: - Helpers

    /// Feed the flagsChanged event the IME normally sees when a modifier goes down.
    private func pressModifier(keyCode: UInt16) {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create flagsChanged event")
            return
        }
        _ = controller.handle(event, client: client)
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create NSEvent")
            fatalError("Failed to create NSEvent")
        }
        return event
    }
}
