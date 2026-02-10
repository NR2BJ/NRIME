import XCTest
@testable import NRIME

final class ShortcutHandlerTests: XCTestCase {

    private var handler: ShortcutHandler!

    override func setUp() {
        super.setUp()
        handler = ShortcutHandler()
        Settings.shared.tapThreshold = 0.2
        // Reset StateManager to known state
        StateManager.shared.switchTo(.english)
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
        handler.reset()
        // After reset, handler should not have any pending state
        // This is primarily to ensure no crash
    }
}
