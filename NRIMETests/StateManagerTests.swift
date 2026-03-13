import XCTest
@testable import NRIME

final class StateManagerTests: XCTestCase {
    private var originalLastNonEnglishMode: InputMode!
    private var originalPerAppModeEnabled: Bool!
    private var originalPerAppModeType: String!
    private var originalPerAppModeList: [String]!
    private var originalPerAppSavedModes: [String: String]!

    override func setUp() {
        super.setUp()
        originalLastNonEnglishMode = Settings.shared.lastNonEnglishMode
        originalPerAppModeEnabled = Settings.shared.perAppModeEnabled
        originalPerAppModeType = Settings.shared.perAppModeType
        originalPerAppModeList = Settings.shared.perAppModeList
        originalPerAppSavedModes = Settings.shared.perAppSavedModes
        StateManager.shared.resetForTesting()
    }

    override func tearDown() {
        Settings.shared.lastNonEnglishMode = originalLastNonEnglishMode
        Settings.shared.perAppModeEnabled = originalPerAppModeEnabled
        Settings.shared.perAppModeType = originalPerAppModeType
        Settings.shared.perAppModeList = originalPerAppModeList
        Settings.shared.perAppSavedModes = originalPerAppSavedModes
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

    func testInitialActivationSkipsPerAppNonEnglishRestore() {
        Settings.shared.perAppModeEnabled = true
        Settings.shared.perAppModeType = "whitelist"
        Settings.shared.perAppModeList = ["com.apple.TextEdit"]
        Settings.shared.perAppSavedModes = [
            "com.apple.TextEdit": InputMode.japanese.rawValue
        ]

        StateManager.shared.activateApp("com.apple.TextEdit")

        XCTAssertEqual(StateManager.shared.currentMode, .english)
    }

    func testSubsequentActivationRestoresPerAppMode() {
        Settings.shared.perAppModeEnabled = true
        Settings.shared.perAppModeType = "whitelist"
        Settings.shared.perAppModeList = ["com.apple.TextEdit", "com.apple.Terminal"]
        Settings.shared.perAppSavedModes = [
            "com.apple.TextEdit": InputMode.japanese.rawValue,
            "com.apple.Terminal": InputMode.korean.rawValue
        ]

        StateManager.shared.activateApp("com.apple.TextEdit")
        StateManager.shared.deactivateApp("com.apple.TextEdit")
        StateManager.shared.activateApp("com.apple.Terminal")

        XCTAssertEqual(StateManager.shared.currentMode, .korean)
    }
}
