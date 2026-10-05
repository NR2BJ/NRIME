import XCTest
@testable import NRIME

final class SettingsTransferTests: XCTestCase {
    private var sourceSuiteName: String!
    private var targetSuiteName: String!
    private var sourceDefaults: UserDefaults!
    private var targetDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        sourceSuiteName = "test.nrime.transfer.source.\(UUID().uuidString)"
        targetSuiteName = "test.nrime.transfer.target.\(UUID().uuidString)"
        sourceDefaults = UserDefaults(suiteName: sourceSuiteName)
        targetDefaults = UserDefaults(suiteName: targetSuiteName)
        sourceDefaults.removePersistentDomain(forName: sourceSuiteName)
        targetDefaults.removePersistentDomain(forName: targetSuiteName)
    }

    override func tearDown() {
        sourceDefaults.removePersistentDomain(forName: sourceSuiteName)
        targetDefaults.removePersistentDomain(forName: targetSuiteName)
        sourceDefaults = nil
        targetDefaults = nil
        sourceSuiteName = nil
        targetSuiteName = nil
        super.tearDown()
    }

    func testSnapshotRoundTripRestoresSettingsAndMemory() throws {
        sourceDefaults.set(0.34, forKey: SettingsTransfer.tapThresholdKey)
        sourceDefaults.set(true, forKey: SettingsTransfer.preventABCSwitchKey)
        sourceDefaults.set(true, forKey: SettingsTransfer.developerModeEnabledKey)
        sourceDefaults.set(InputMode.japanese.rawValue, forKey: SettingsTransfer.lastNonEnglishModeKey)
        sourceDefaults.set(
            try JSONEncoder().encode(ShortcutConfig.defaultHanjaConvert),
            forKey: SettingsTransfer.shortcutKey(for: "hanjaConvert")
        )
        sourceDefaults.set(
            try JSONEncoder().encode(JapaneseKeyConfig.default),
            forKey: SettingsTransfer.japaneseKeyConfigKey
        )
        sourceDefaults.set(
            try JSONEncoder().encode([HanjaSelectionEntry(hangul: "사", hanja: "社")]),
            forKey: HanjaSelectionStore.defaultsKey
        )

        let snapshot = SettingsTransfer.capture(from: sourceDefaults, appVersion: "1.0.3")
        let encoded = try SettingsTransfer.encode(snapshot)
        let decoded = try SettingsTransfer.decode(from: encoded)
        SettingsTransfer.apply(decoded, to: targetDefaults)

        XCTAssertEqual(targetDefaults.double(forKey: SettingsTransfer.tapThresholdKey), 0.34, accuracy: 0.0001)
        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.preventABCSwitchKey), true)
        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.developerModeEnabledKey), true)
        XCTAssertEqual(targetDefaults.string(forKey: SettingsTransfer.lastNonEnglishModeKey), InputMode.japanese.rawValue)
        XCTAssertNotNil(targetDefaults.data(forKey: SettingsTransfer.shortcutKey(for: "hanjaConvert")))
        XCTAssertNotNil(targetDefaults.data(forKey: SettingsTransfer.japaneseKeyConfigKey))
        XCTAssertNotNil(targetDefaults.data(forKey: HanjaSelectionStore.defaultsKey))
    }

    func testApplyClearsOptionalDataThatIsMissingFromSnapshot() throws {
        targetDefaults.set(Data([1, 2, 3]), forKey: SettingsTransfer.shortcutKey(for: "toggleEnglish"))
        targetDefaults.set(Data([4, 5, 6]), forKey: SettingsTransfer.japaneseKeyConfigKey)
        targetDefaults.set(Data([7, 8, 9]), forKey: HanjaSelectionStore.defaultsKey)

        let emptySnapshot = SettingsTransferSnapshot(
            schemaVersion: SettingsTransferSnapshot.currentSchemaVersion,
            exportedAt: Date(),
            appVersion: "1.0.3",
            tapThreshold: 0.2,
            preventABCSwitch: false,
            developerModeEnabled: false,
            lastNonEnglishMode: nil,
            shortcutData: [:],
            japaneseKeyConfigData: nil,
            hanjaSelectionMemoryData: nil
        )

        SettingsTransfer.apply(emptySnapshot, to: targetDefaults)

        XCTAssertNil(targetDefaults.data(forKey: SettingsTransfer.shortcutKey(for: "toggleEnglish")))
        XCTAssertNil(targetDefaults.data(forKey: SettingsTransfer.japaneseKeyConfigKey))
        XCTAssertNil(targetDefaults.data(forKey: HanjaSelectionStore.defaultsKey))
    }

    /// The user's Korean/Japanese toggle lives in toggleNonEnglish, which the
    /// first schema never captured — an export written before it existed must
    /// not be read as "the user cleared that shortcut".
    func testOlderSnapshotDoesNotClearShortcutsItCouldNotHaveCaptured() throws {
        let existing = Data([9, 9, 9])
        targetDefaults.set(existing, forKey: SettingsTransfer.shortcutKey(for: "toggleNonEnglish"))

        var snapshot = SettingsTransfer.capture(from: sourceDefaults, appVersion: "1.0.3")
        snapshot.shortcutData.removeValue(forKey: "toggleNonEnglish")
        snapshot.capturedShortcutNames = nil // as written by the first schema

        SettingsTransfer.apply(snapshot, to: targetDefaults)

        XCTAssertEqual(targetDefaults.data(forKey: SettingsTransfer.shortcutKey(for: "toggleNonEnglish")),
                       existing)
    }

    func testSnapshotCarriesTheKeyTimingSettings() throws {
        sourceDefaults.set(true, forKey: "tapHoldBufferingEnabled")

        let snapshot = SettingsTransfer.capture(from: sourceDefaults, appVersion: "1.0.11")
        SettingsTransfer.apply(snapshot, to: targetDefaults)

        XCTAssertTrue(targetDefaults.bool(forKey: "tapHoldBufferingEnabled"))
    }

    /// The key-press app list travels with the settings; the waits do not
    /// (the right value differs from Mac to Mac).
    func testKeyPressAppsTravelButTheWaitsDoNot() throws {
        sourceDefaults.set(["com.openai.codex", "com.example.chat"], forKey: NewlineKeyPress.appsKey)
        sourceDefaults.set(35, forKey: "newlineInsertWaitMs")

        let snapshot = SettingsTransfer.capture(from: sourceDefaults, appVersion: "1.0.12")
        let decoded = try SettingsTransfer.decode(from: SettingsTransfer.encode(snapshot))
        SettingsTransfer.apply(decoded, to: targetDefaults)

        XCTAssertEqual(targetDefaults.stringArray(forKey: NewlineKeyPress.appsKey),
                       ["com.openai.codex", "com.example.chat"])
        XCTAssertNil(targetDefaults.object(forKey: "newlineInsertWaitMs"))
    }

    /// Exports written before the per-app, double-tap, direct-switch,
    /// newline-wait, tap-window and mode-indicator settings were removed still
    /// import: their extra keys are ignored.
    func testExportWithRemovedSettingsStillImports() throws {
        let legacy = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-07-22T09:00:00Z",
          "appVersion": "1.0.10",
          "inlineIndicatorEnabled": true,
          "indicatorPositionMode": "mouse",
          "tapThreshold": 0.25,
          "preventABCSwitch": false,
          "developerModeEnabled": true,
          "perAppModeEnabled": true,
          "perAppModeType": "whitelist",
          "perAppModeList": ["com.apple.TextEdit"],
          "perAppSavedModes": {"com.apple.TextEdit": "com.nrime.inputmethod.app.ja"},
          "shiftDoubleTapEnabled": true,
          "doubleTapWindow": 0.3,
          "shiftEnterDelay": 0.035,
          "codexNewlineDelay": 0.12,
          "tapOverlapWindow": 0.07,
          "shortcutData": {},
          "capturedShortcutNames": ["toggleEnglish", "toggleNonEnglish", "switchKorean", "switchJapanese", "hanjaConvert"]
        }
        """
        let snapshot = try SettingsTransfer.decode(from: Data(legacy.utf8))
        SettingsTransfer.apply(snapshot, to: targetDefaults)

        XCTAssertEqual(targetDefaults.double(forKey: SettingsTransfer.tapThresholdKey), 0.25, accuracy: 0.0001)
        XCTAssertNil(targetDefaults.object(forKey: "perAppModeEnabled"), "Removed settings are not written back")
        XCTAssertNil(targetDefaults.object(forKey: "shiftDoubleTapEnabled"))
        XCTAssertNil(targetDefaults.object(forKey: "shiftEnterDelay"), "The newline no longer waits")
        XCTAssertNil(targetDefaults.object(forKey: "codexNewlineDelay"))
        XCTAssertNil(targetDefaults.object(forKey: "tapOverlapWindow"), "The tap windows are fixed now")
        XCTAssertNil(targetDefaults.object(forKey: "inlineIndicatorEnabled"), "The mode indicator is gone")
        XCTAssertNil(targetDefaults.object(forKey: "indicatorPositionMode"))
        XCTAssertNil(targetDefaults.object(forKey: NewlineKeyPress.appsKey),
                     "An export that knew nothing of the list leaves this Mac's list alone")
    }
}
