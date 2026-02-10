import Cocoa
import Combine

/// Observable settings store that reads/writes from App Group UserDefaults.
/// Mirrors the Settings class used by the input method process.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init() {
        let suiteName = "group.com.nrime.inputmethod"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard

        // Load initial values
        _inlineIndicatorEnabled = Published(initialValue:
            defaults.object(forKey: "inlineIndicatorEnabled") == nil ? true : defaults.bool(forKey: "inlineIndicatorEnabled")
        )
        let tapVal = defaults.double(forKey: "tapThreshold")
        _tapThreshold = Published(initialValue: tapVal > 0 ? tapVal : 0.2)
        _perAppModeEnabled = Published(initialValue: defaults.bool(forKey: "perAppModeEnabled"))
        _perAppModeType = Published(initialValue: defaults.string(forKey: "perAppModeType") ?? "whitelist")
        _perAppModeList = Published(initialValue: defaults.stringArray(forKey: "perAppModeList") ?? [])

        // Load shortcuts
        _toggleEnglishShortcut = Published(initialValue: Self.loadShortcut("toggleEnglish", from: defaults) ?? .defaultToggleEnglish)
        _switchKoreanShortcut = Published(initialValue: Self.loadShortcut("switchKorean", from: defaults) ?? .defaultSwitchKorean)
        _switchJapaneseShortcut = Published(initialValue: Self.loadShortcut("switchJapanese", from: defaults) ?? .defaultSwitchJapanese)
        _hanjaConvertShortcut = Published(initialValue: Self.loadShortcut("hanjaConvert", from: defaults) ?? .defaultHanjaConvert)
    }

    // MARK: - Shortcuts

    @Published var toggleEnglishShortcut: ShortcutConfig {
        didSet { saveShortcut(toggleEnglishShortcut, for: "toggleEnglish") }
    }
    @Published var switchKoreanShortcut: ShortcutConfig {
        didSet { saveShortcut(switchKoreanShortcut, for: "switchKorean") }
    }
    @Published var switchJapaneseShortcut: ShortcutConfig {
        didSet { saveShortcut(switchJapaneseShortcut, for: "switchJapanese") }
    }
    @Published var hanjaConvertShortcut: ShortcutConfig {
        didSet { saveShortcut(hanjaConvertShortcut, for: "hanjaConvert") }
    }

    // MARK: - General Settings

    @Published var inlineIndicatorEnabled: Bool {
        didSet { defaults.set(inlineIndicatorEnabled, forKey: "inlineIndicatorEnabled") }
    }

    @Published var tapThreshold: Double {
        didSet { defaults.set(tapThreshold, forKey: "tapThreshold") }
    }

    // MARK: - Per-App Mode

    @Published var perAppModeEnabled: Bool {
        didSet { defaults.set(perAppModeEnabled, forKey: "perAppModeEnabled") }
    }

    @Published var perAppModeType: String {
        didSet { defaults.set(perAppModeType, forKey: "perAppModeType") }
    }

    @Published var perAppModeList: [String] {
        didSet { defaults.set(perAppModeList, forKey: "perAppModeList") }
    }

    // MARK: - Private

    private static func loadShortcut(_ key: String, from defaults: UserDefaults) -> ShortcutConfig? {
        guard let data = defaults.data(forKey: "shortcut_\(key)"),
              let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else {
            return nil
        }
        return config
    }

    private func saveShortcut(_ config: ShortcutConfig, for key: String) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "shortcut_\(key)")
        }
    }
}

/// Shortcut configuration — must match Settings.ShortcutConfig in the input method.
struct ShortcutConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifierKeyCode: UInt16
    var modifiers: UInt
    var isModifierOnlyTap: Bool
    var label: String

    static let defaultToggleEnglish = ShortcutConfig(
        keyCode: 0x3C, modifierKeyCode: 0x3C,
        modifiers: 0, isModifierOnlyTap: true, label: "Right Shift"
    )
    static let defaultSwitchKorean = ShortcutConfig(
        keyCode: 0x12, modifierKeyCode: 0x3C,
        modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
        isModifierOnlyTap: false, label: "Right Shift + 1"
    )
    static let defaultSwitchJapanese = ShortcutConfig(
        keyCode: 0x13, modifierKeyCode: 0x3C,
        modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
        isModifierOnlyTap: false, label: "Right Shift + 2"
    )
    static let defaultHanjaConvert = ShortcutConfig(
        keyCode: 0x24, modifierKeyCode: 0x3A,
        modifiers: UInt(NSEvent.ModifierFlags.option.rawValue),
        isModifierOnlyTap: false, label: "Option + Enter"
    )
}
