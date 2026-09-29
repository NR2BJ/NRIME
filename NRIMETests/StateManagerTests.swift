import XCTest
@testable import NRIME

final class StateManagerTests: XCTestCase {
    private var originalLastNonEnglishMode: InputMode!

    override func setUp() {
        super.setUp()
        originalLastNonEnglishMode = Settings.shared.lastNonEnglishMode
        StateManager.shared.resetForTesting()
    }

    override func tearDown() {
        Settings.shared.lastNonEnglishMode = originalLastNonEnglishMode
        StateManager.shared.reloadPersistedModePreferences()
        StateManager.shared.resetForTesting()
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

    /// Per-app mode memory was removed: the mode is global, and moving between
    /// apps never changes it — even when an old per-app record is still stored.
    func testActivatingAnAppNeverChangesTheMode() {
        let defaults = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)
        defaults?.set(true, forKey: "perAppModeEnabled")
        defaults?.set("whitelist", forKey: "perAppModeType")
        defaults?.set(["com.apple.TextEdit"], forKey: "perAppModeList")
        defaults?.set(["com.apple.TextEdit": InputMode.japanese.rawValue], forKey: "perAppSavedModes")
        defer {
            for key in ["perAppModeEnabled", "perAppModeType", "perAppModeList", "perAppSavedModes"] {
                defaults?.removeObject(forKey: key)
            }
        }
        StateManager.shared.switchTo(.korean)

        StateManager.shared.activateApp("com.apple.Terminal")
        StateManager.shared.activateApp("com.apple.TextEdit")

        XCTAssertEqual(StateManager.shared.currentMode, .korean)
    }
}
