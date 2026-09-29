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
    // Per-app mode memory (perAppMode*) was removed on 2026-09-29. Older
    // exports still carry those keys; decoding ignores them.
    var lastNonEnglishMode: String?
    var shortcutData: [String: Data]
    var japaneseKeyConfigData: Data?
    var hanjaSelectionMemoryData: Data?

    // Added after the first schema. Optional so exports written before they
    // existed still decode; `nil` means "this export knew nothing about it",
    // which is different from "the user turned it off".
    var indicatorPositionMode: String?
    var shiftEnterDelay: Double?
    var codexNewlineDelay: Double?
    var tapHoldBufferingEnabled: Bool?
    var tapOverlapWindow: Double?
    var secureInputASCIIFallback: Bool?
    /// Which shortcuts this export actually looked at. Without it a newer
    /// import would read an older export's silence as "clear that shortcut".
    var capturedShortcutNames: [String]?
}

enum SettingsTransfer {
    static let inlineIndicatorEnabledKey = "inlineIndicatorEnabled"
    static let tapThresholdKey = "tapThreshold"
    static let preventABCSwitchKey = "preventABCSwitch"
    static let developerModeEnabledKey = "developerModeEnabled"
    static let lastNonEnglishModeKey = "lastNonEnglishMode"
    static let japaneseKeyConfigKey = "japaneseKeyConfig"

    static let indicatorPositionModeKey = "indicatorPositionMode"
    static let shiftEnterDelayKey = "shiftEnterDelay"
    static let codexNewlineDelayKey = "codexNewlineDelay"
    static let tapHoldBufferingEnabledKey = "tapHoldBufferingEnabled"
    static let tapOverlapWindowKey = "tapOverlapWindow"
    static let secureInputASCIIFallbackKey = "secureInputASCIIFallback"

    /// Shortcut names present in the first schema version (of those still in
    /// use — the Korean/Japanese direct-switch shortcuts were removed).
    private static let originalShortcutNames: Set<String> = [
        "toggleEnglish",
        "hanjaConvert",
    ]

    static let shortcutNames = [
        "toggleEnglish",
        "toggleNonEnglish",
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
            lastNonEnglishMode: defaults.string(forKey: lastNonEnglishModeKey),
            shortcutData: shortcutData,
            japaneseKeyConfigData: defaults.data(forKey: japaneseKeyConfigKey),
            hanjaSelectionMemoryData: defaults.data(forKey: HanjaSelectionStore.defaultsKey),
            indicatorPositionMode: defaults.string(forKey: indicatorPositionModeKey) ?? "caret",
            // 0 is a real value (no wait), not "unset".
            shiftEnterDelay: defaults.object(forKey: shiftEnterDelayKey) == nil
                ? 0 : defaults.double(forKey: shiftEnterDelayKey),
            codexNewlineDelay: defaults.object(forKey: codexNewlineDelayKey) == nil
                ? 0 : defaults.double(forKey: codexNewlineDelayKey),
            tapHoldBufferingEnabled: defaults.bool(forKey: tapHoldBufferingEnabledKey),
            tapOverlapWindow: defaults.double(forKey: tapOverlapWindowKey) > 0
                ? defaults.double(forKey: tapOverlapWindowKey)
                : 0.05,
            secureInputASCIIFallback: defaults.object(forKey: secureInputASCIIFallbackKey) == nil
                ? true
                : defaults.bool(forKey: secureInputASCIIFallbackKey),
            capturedShortcutNames: shortcutNames
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

        if let mode = snapshot.lastNonEnglishMode, !mode.isEmpty {
            defaults.set(mode, forKey: lastNonEnglishModeKey)
        } else {
            defaults.removeObject(forKey: lastNonEnglishModeKey)
        }

        // A value the export never carried must not overwrite this Mac's.
        if let value = snapshot.indicatorPositionMode {
            defaults.set(value, forKey: indicatorPositionModeKey)
        }
        if let value = snapshot.shiftEnterDelay {
            defaults.set(value, forKey: shiftEnterDelayKey)
        }
        if let value = snapshot.codexNewlineDelay {
            defaults.set(value, forKey: codexNewlineDelayKey)
        }
        if let value = snapshot.tapHoldBufferingEnabled {
            defaults.set(value, forKey: tapHoldBufferingEnabledKey)
        }
        if let value = snapshot.tapOverlapWindow {
            defaults.set(value, forKey: tapOverlapWindowKey)
        }
        if let value = snapshot.secureInputASCIIFallback {
            defaults.set(value, forKey: secureInputASCIIFallbackKey)
        }

        // Clearing a shortcut only transfers when the export was in a position
        // to record it. The first schema already captured the original names,
        // so silence there genuinely means "none set"; names added later were
        // invisible to those exports and must not be wiped by their silence.
        let knownShortcutNames = snapshot.capturedShortcutNames.map(Set.init)
            ?? originalShortcutNames
        for name in shortcutNames {
            let key = shortcutKey(for: name)
            if let data = snapshot.shortcutData[name] {
                defaults.set(data, forKey: key)
            } else if knownShortcutNames.contains(name) {
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
