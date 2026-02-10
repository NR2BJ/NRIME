import Cocoa

/// Shared settings between the input method and Companion App.
/// Uses App Group UserDefaults (suiteName) for cross-process synchronization.
final class Settings {
    static let shared = Settings()

    static let suiteName = "group.com.nrime.inputmethod"

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Settings.suiteName) ?? UserDefaults.standard
    }

    // MARK: - Shortcut Keys

    /// Stored shortcut configuration. Each shortcut is serialized as a dictionary.
    /// Keys: "toggleEnglish", "switchKorean", "switchJapanese", "hanjaConvert"

    struct ShortcutConfig: Codable, Equatable {
        /// For modifier-only tap: the modifier's hardware keyCode (e.g. 0x3C = Right Shift)
        /// For modifier+key combo: the non-modifier key's keyCode (e.g. 0x12 = "1")
        /// For plain key: the key's keyCode (e.g. 0x69 = F13)
        var keyCode: UInt16

        /// For modifier+key combo: the modifier's hardware keyCode (e.g. 0x3C for Right Shift)
        /// For modifier-only tap or plain key: same as keyCode
        var modifierKeyCode: UInt16

        /// Required modifier flags (high-level: .shift, .option, .control, .command)
        var modifiers: UInt

        /// true if this shortcut fires on modifier key tap (no other key involved)
        var isModifierOnlyTap: Bool

        /// Display label, e.g. "Right Shift", "Right Shift + 1"
        var label: String

        // MARK: - Modifier keyCode constants
        static let keyCodeRightShift: UInt16  = 0x3C
        static let keyCodeLeftShift: UInt16   = 0x38
        static let keyCodeRightCtrl: UInt16   = 0x3E
        static let keyCodeLeftCtrl: UInt16    = 0x3B
        static let keyCodeRightOption: UInt16 = 0x3D
        static let keyCodeLeftOption: UInt16  = 0x3A
        static let keyCodeRightCmd: UInt16    = 0x36
        static let keyCodeLeftCmd: UInt16     = 0x37
        static let keyCodeCapsLock: UInt16    = 0x39

        /// Which high-level modifier flag this modifier keyCode belongs to
        static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
            switch keyCode {
            case keyCodeRightShift, keyCodeLeftShift:   return .shift
            case keyCodeRightCtrl, keyCodeLeftCtrl:     return .control
            case keyCodeRightOption, keyCodeLeftOption:  return .option
            case keyCodeRightCmd, keyCodeLeftCmd:        return .command
            default: return nil
            }
        }

        /// Is this keyCode a modifier key?
        static func isModifierKey(_ keyCode: UInt16) -> Bool {
            return modifierFlag(for: keyCode) != nil || keyCode == keyCodeCapsLock
        }

        /// Default: Right Shift tap
        static let defaultToggleEnglish = ShortcutConfig(
            keyCode: keyCodeRightShift, modifierKeyCode: keyCodeRightShift,
            modifiers: 0, isModifierOnlyTap: true, label: "Right Shift"
        )
        /// Default: Right Shift + 1
        static let defaultSwitchKorean = ShortcutConfig(
            keyCode: 0x12, modifierKeyCode: keyCodeRightShift,
            modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
            isModifierOnlyTap: false, label: "Right Shift + 1"
        )
        /// Default: Right Shift + 2
        static let defaultSwitchJapanese = ShortcutConfig(
            keyCode: 0x13, modifierKeyCode: keyCodeRightShift,
            modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
            isModifierOnlyTap: false, label: "Right Shift + 2"
        )
        /// Default: Option + Enter
        static let defaultHanjaConvert = ShortcutConfig(
            keyCode: 0x24, modifierKeyCode: keyCodeLeftOption,
            modifiers: UInt(NSEvent.ModifierFlags.option.rawValue),
            isModifierOnlyTap: false, label: "Option + Enter"
        )
    }

    func shortcut(for key: String) -> ShortcutConfig {
        guard let data = defaults.data(forKey: "shortcut_\(key)"),
              let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else {
            switch key {
            case "toggleEnglish": return .defaultToggleEnglish
            case "switchKorean": return .defaultSwitchKorean
            case "switchJapanese": return .defaultSwitchJapanese
            case "hanjaConvert": return .defaultHanjaConvert
            default: return .defaultToggleEnglish
            }
        }
        return config
    }

    func setShortcut(_ config: ShortcutConfig, for key: String) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "shortcut_\(key)")
        }
    }

    // MARK: - Tap Threshold

    var tapThreshold: TimeInterval {
        get {
            let val = defaults.double(forKey: "tapThreshold")
            return val > 0 ? val : 0.2
        }
        set { defaults.set(newValue, forKey: "tapThreshold") }
    }

    // MARK: - Inline Indicator

    var inlineIndicatorEnabled: Bool {
        get {
            if defaults.object(forKey: "inlineIndicatorEnabled") == nil { return true }
            return defaults.bool(forKey: "inlineIndicatorEnabled")
        }
        set { defaults.set(newValue, forKey: "inlineIndicatorEnabled") }
    }

    // MARK: - Per-App Mode Memory

    var perAppModeEnabled: Bool {
        get { defaults.bool(forKey: "perAppModeEnabled") }
        set { defaults.set(newValue, forKey: "perAppModeEnabled") }
    }

    /// "whitelist" or "blacklist"
    var perAppModeType: String {
        get { defaults.string(forKey: "perAppModeType") ?? "whitelist" }
        set { defaults.set(newValue, forKey: "perAppModeType") }
    }

    /// Bundle IDs in the whitelist/blacklist
    var perAppModeList: [String] {
        get { defaults.stringArray(forKey: "perAppModeList") ?? [] }
        set { defaults.set(newValue, forKey: "perAppModeList") }
    }

    /// Per-app saved modes: [bundleId: InputMode.rawValue]
    var perAppSavedModes: [String: String] {
        get { defaults.dictionary(forKey: "perAppSavedModes") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "perAppSavedModes") }
    }

    // MARK: - Sync

    func synchronize() {
        defaults.synchronize()
    }
}
