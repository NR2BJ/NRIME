import Cocoa
import XCTest
@testable import NRIME

final class ShortcutHandlerTests: XCTestCase {

    private var handler: ShortcutHandler!
    private var originalToggleEnglish: ShortcutConfig!
    private var originalSwitchKorean: ShortcutConfig!
    private var originalSwitchJapanese: ShortcutConfig!
    private var originalHanjaConvert: ShortcutConfig!
    private var originalTapThreshold: TimeInterval = 0

    override func setUp() {
        super.setUp()
        handler = ShortcutHandler()
        originalToggleEnglish = Settings.shared.shortcut(for: "toggleEnglish")
        originalSwitchKorean = Settings.shared.shortcut(for: "switchKorean")
        originalSwitchJapanese = Settings.shared.shortcut(for: "switchJapanese")
        originalHanjaConvert = Settings.shared.shortcut(for: "hanjaConvert")
        originalTapThreshold = Settings.shared.tapThreshold
        Settings.shared.tapThreshold = 0.2
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(.defaultSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(.defaultSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(.defaultHanjaConvert, for: "hanjaConvert")
        // Reset StateManager to known state
        StateManager.shared.switchTo(.korean)
        StateManager.shared.switchTo(.english)
    }

    override func tearDown() {
        Settings.shared.setShortcut(originalToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(originalSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(originalSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(originalHanjaConvert, for: "hanjaConvert")
        Settings.shared.tapThreshold = originalTapThreshold
        handler = nil
        super.tearDown()
    }

    // MARK: - Note: NSEvent creation in tests

    // NSEvent creation for flagsChanged and keyDown requires careful construction.
    // These tests verify the ShortcutHandler logic using real NSEvents where possible,
    // and document expected behavior for cases that are hard to test without the full
    // InputMethodKit runtime.

    func testInitialState() {
        // StateManager starts in English mode
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    func testToggleLogic() {
        // Verify StateManager toggle works correctly
        StateManager.shared.toggleEnglish()
        XCTAssertEqual(StateManager.shared.currentMode, .korean)

        StateManager.shared.toggleEnglish()
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    func testSwitchDirectly() {
        StateManager.shared.switchTo(.korean)
        XCTAssertEqual(StateManager.shared.currentMode, .korean)

        StateManager.shared.switchTo(.english)
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    func testSwitchToSameMode() {
        StateManager.shared.switchTo(.english)
        // Switching to the same mode should not trigger callback
        var callbackCalled = false
        StateManager.shared.onModeChanged = { _ in callbackCalled = true }
        StateManager.shared.switchTo(.english) // Same mode
        XCTAssertFalse(callbackCalled)
    }

    func testPreviousModeMemory() {
        // Start in English, switch to Korean, then toggle back
        StateManager.shared.switchTo(.korean)
        StateManager.shared.toggleEnglish() // → English
        XCTAssertEqual(StateManager.shared.currentMode, .english)
        StateManager.shared.toggleEnglish() // → Korean (remembered)
        XCTAssertEqual(StateManager.shared.currentMode, .korean)
    }

    func testResetHandler() {
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: [.shift]
        )))
        handler.reset()
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: []
        )))
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    func testModifierOnlyTapTriggersToggleEnglish() {
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: [.shift]
        )))
        XCTAssertTrue(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: []
        )))
        XCTAssertEqual(StateManager.shared.currentMode, .korean)
    }

    func testModifierComboSwitchesJapanese() {
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: [.shift]
        )))
        XCTAssertTrue(handler.handleEvent(keyEvent(
            keyCode: 0x13,
            characters: "2",
            modifiers: [.shift]
        )))
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    func testModifierComboSuppressesTapActionOnRelease() {
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: [.shift]
        )))
        XCTAssertTrue(handler.handleEvent(keyEvent(
            keyCode: 0x13,
            characters: "2",
            modifiers: [.shift]
        )))
        XCTAssertFalse(handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: []
        )))
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    // MARK: - Timing under main-thread stalls

    /// Tap timing must come from the events' own timestamps, not from when the
    /// handler happened to run. The IMKit event thread can stall for hundreds of
    /// milliseconds (synchronous Mozc IPC, server relaunch sleeps), which delays
    /// the release's *processing* without changing how long the key was held.
    func testTapStillFiresWhenEventProcessingIsDelayed() {
        let stall: TimeInterval = 0.30 // > tapThreshold (0.2)
        StateManager.shared.switchTo(.korean)

        _ = handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift, modifiers: [.shift], timestamp: 100.0))
        Thread.sleep(forTimeInterval: stall)
        let consumed = handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift, modifiers: [], timestamp: 100.08))

        XCTAssertTrue(consumed, "An 80ms physical tap must fire even if its release was processed late")
        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    /// The mirror case: a genuinely long hold must not be promoted to a tap just
    /// because the handler processed both events back to back.
    func testLongHoldIsNotTreatedAsTapWhenProcessedQuickly() {
        StateManager.shared.switchTo(.korean)

        _ = handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift, modifiers: [.shift], timestamp: 200.0))
        let consumed = handler.handleEvent(flagsChangedEvent(
            keyCode: ShortcutConfig.keyCodeRightShift, modifiers: [], timestamp: 200.5))

        XCTAssertFalse(consumed, "500ms hold is not a tap")
        XCTAssertEqual(StateManager.shared.currentMode, .korean)
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

    private func flagsChangedEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        timestamp: TimeInterval = 0
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create flagsChanged NSEvent")
            fatalError("Failed to create flagsChanged NSEvent")
        }
        return event
    }
}
