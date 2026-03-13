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
        sourceDefaults.set(false, forKey: SettingsTransfer.inlineIndicatorEnabledKey)
        sourceDefaults.set(0.34, forKey: SettingsTransfer.tapThresholdKey)
        sourceDefaults.set(true, forKey: SettingsTransfer.preventABCSwitchKey)
        sourceDefaults.set(true, forKey: SettingsTransfer.developerModeEnabledKey)
        sourceDefaults.set(true, forKey: SettingsTransfer.perAppModeEnabledKey)
        sourceDefaults.set("blacklist", forKey: SettingsTransfer.perAppModeTypeKey)
        sourceDefaults.set(["com.apple.Terminal"], forKey: SettingsTransfer.perAppModeListKey)
        sourceDefaults.set(["com.apple.Terminal": InputMode.english.rawValue], forKey: SettingsTransfer.perAppSavedModesKey)
        sourceDefaults.set(InputMode.japanese.rawValue, forKey: SettingsTransfer.lastNonEnglishModeKey)
        sourceDefaults.set(
            try JSONEncoder().encode(Settings.ShortcutConfig.defaultSwitchJapanese),
            forKey: SettingsTransfer.shortcutKey(for: "switchJapanese")
        )
        sourceDefaults.set(
            try JSONEncoder().encode(Settings.JapaneseKeyConfig.default),
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

        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.inlineIndicatorEnabledKey), false)
        XCTAssertEqual(targetDefaults.double(forKey: SettingsTransfer.tapThresholdKey), 0.34, accuracy: 0.0001)
        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.preventABCSwitchKey), true)
        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.developerModeEnabledKey), true)
        XCTAssertEqual(targetDefaults.bool(forKey: SettingsTransfer.perAppModeEnabledKey), true)
        XCTAssertEqual(targetDefaults.string(forKey: SettingsTransfer.perAppModeTypeKey), "blacklist")
        XCTAssertEqual(targetDefaults.stringArray(forKey: SettingsTransfer.perAppModeListKey), ["com.apple.Terminal"])
        XCTAssertEqual(
            targetDefaults.dictionary(forKey: SettingsTransfer.perAppSavedModesKey) as? [String: String],
            ["com.apple.Terminal": InputMode.english.rawValue]
        )
        XCTAssertEqual(targetDefaults.string(forKey: SettingsTransfer.lastNonEnglishModeKey), InputMode.japanese.rawValue)
        XCTAssertNotNil(targetDefaults.data(forKey: SettingsTransfer.shortcutKey(for: "switchJapanese")))
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
            inlineIndicatorEnabled: true,
            tapThreshold: 0.2,
            preventABCSwitch: false,
            developerModeEnabled: false,
            perAppModeEnabled: false,
            perAppModeType: "whitelist",
            perAppModeList: [],
            perAppSavedModes: [:],
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
}
