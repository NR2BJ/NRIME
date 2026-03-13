import Foundation

struct SettingsTransferSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String?
    var inlineIndicatorEnabled: Bool
    var tapThreshold: Double
    var preventABCSwitch: Bool
    var developerModeEnabled: Bool
    var perAppModeEnabled: Bool
    var perAppModeType: String
    var perAppModeList: [String]
    var perAppSavedModes: [String: String]
    var lastNonEnglishMode: String?
    var shortcutData: [String: Data]
    var japaneseKeyConfigData: Data?
    var hanjaSelectionMemoryData: Data?
}

enum SettingsTransfer {
    static let inlineIndicatorEnabledKey = "inlineIndicatorEnabled"
    static let tapThresholdKey = "tapThreshold"
    static let preventABCSwitchKey = "preventABCSwitch"
    static let developerModeEnabledKey = "developerModeEnabled"
    static let perAppModeEnabledKey = "perAppModeEnabled"
    static let perAppModeTypeKey = "perAppModeType"
    static let perAppModeListKey = "perAppModeList"
    static let perAppSavedModesKey = "perAppSavedModes"
    static let lastNonEnglishModeKey = "lastNonEnglishMode"
    static let japaneseKeyConfigKey = "japaneseKeyConfig"

    static let shortcutNames = [
        "toggleEnglish",
        "switchKorean",
        "switchJapanese",
        "hanjaConvert",
    ]

    static func capture(from defaults: UserDefaults, appVersion: String? = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String) -> SettingsTransferSnapshot {
        var shortcutData: [String: Data] = [:]
        for name in shortcutNames {
            let key = shortcutKey(for: name)
            if let data = defaults.data(forKey: key) {
                shortcutData[name] = data
            }
        }

        return SettingsTransferSnapshot(
            schemaVersion: SettingsTransferSnapshot.currentSchemaVersion,
            exportedAt: Date(),
            appVersion: appVersion,
            inlineIndicatorEnabled: defaults.object(forKey: inlineIndicatorEnabledKey) == nil
                ? true
                : defaults.bool(forKey: inlineIndicatorEnabledKey),
            tapThreshold: defaults.double(forKey: tapThresholdKey) > 0
                ? defaults.double(forKey: tapThresholdKey)
                : 0.2,
            preventABCSwitch: defaults.bool(forKey: preventABCSwitchKey),
            developerModeEnabled: defaults.bool(forKey: developerModeEnabledKey),
            perAppModeEnabled: defaults.bool(forKey: perAppModeEnabledKey),
            perAppModeType: defaults.string(forKey: perAppModeTypeKey) ?? "whitelist",
            perAppModeList: defaults.stringArray(forKey: perAppModeListKey) ?? [],
            perAppSavedModes: defaults.dictionary(forKey: perAppSavedModesKey) as? [String: String] ?? [:],
            lastNonEnglishMode: defaults.string(forKey: lastNonEnglishModeKey),
            shortcutData: shortcutData,
            japaneseKeyConfigData: defaults.data(forKey: japaneseKeyConfigKey),
            hanjaSelectionMemoryData: defaults.data(forKey: HanjaSelectionStore.defaultsKey)
        )
    }

    static func encode(_ snapshot: SettingsTransferSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(from data: Data) throws -> SettingsTransferSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(SettingsTransferSnapshot.self, from: data)
        guard snapshot.schemaVersion == SettingsTransferSnapshot.currentSchemaVersion else {
            throw SettingsTransferError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }

    static func apply(_ snapshot: SettingsTransferSnapshot, to defaults: UserDefaults) {
        defaults.set(snapshot.inlineIndicatorEnabled, forKey: inlineIndicatorEnabledKey)
        defaults.set(snapshot.tapThreshold, forKey: tapThresholdKey)
        defaults.set(snapshot.preventABCSwitch, forKey: preventABCSwitchKey)
        defaults.set(snapshot.developerModeEnabled, forKey: developerModeEnabledKey)
        defaults.set(snapshot.perAppModeEnabled, forKey: perAppModeEnabledKey)
        defaults.set(snapshot.perAppModeType, forKey: perAppModeTypeKey)
        defaults.set(snapshot.perAppModeList, forKey: perAppModeListKey)
        defaults.set(snapshot.perAppSavedModes, forKey: perAppSavedModesKey)

        if let mode = snapshot.lastNonEnglishMode, !mode.isEmpty {
            defaults.set(mode, forKey: lastNonEnglishModeKey)
        } else {
            defaults.removeObject(forKey: lastNonEnglishModeKey)
        }

        for name in shortcutNames {
            let key = shortcutKey(for: name)
            if let data = snapshot.shortcutData[name] {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        if let data = snapshot.japaneseKeyConfigData {
            defaults.set(data, forKey: japaneseKeyConfigKey)
        } else {
            defaults.removeObject(forKey: japaneseKeyConfigKey)
        }

        if let data = snapshot.hanjaSelectionMemoryData {
            defaults.set(data, forKey: HanjaSelectionStore.defaultsKey)
        } else {
            defaults.removeObject(forKey: HanjaSelectionStore.defaultsKey)
        }

        defaults.synchronize()
    }

    static func shortcutKey(for name: String) -> String {
        "shortcut_\(name)"
    }
}

enum SettingsTransferError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported settings file format (schema \(version))."
        }
    }
}
