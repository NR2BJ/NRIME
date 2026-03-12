import XCTest
@testable import NRIME

final class StateManagerTests: XCTestCase {
    private var originalLastNonEnglishMode: InputMode!

    override func setUp() {
        super.setUp()
        originalLastNonEnglishMode = Settings.shared.lastNonEnglishMode
        StateManager.shared.switchTo(.english)
    }

    override func tearDown() {
        Settings.shared.lastNonEnglishMode = originalLastNonEnglishMode
        StateManager.shared.reloadPersistedModePreferences()
        StateManager.shared.switchTo(.english)
        super.tearDown()
    }

    func testSwitchingToNonEnglishPersistsLastNonEnglishMode() {
        StateManager.shared.switchTo(.japanese)

        XCTAssertEqual(Settings.shared.lastNonEnglishMode, .japanese)
    }

    func testToggleEnglishRestoresPersistedLastNonEnglishMode() {
        Settings.shared.lastNonEnglishMode = .japanese
        StateManager.shared.reloadPersistedModePreferences()

        StateManager.shared.toggleEnglish()

        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }
}
