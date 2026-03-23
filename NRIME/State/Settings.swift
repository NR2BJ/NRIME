import Cocoa

/// Shared settings between the input method and Companion App.
/// Uses App Group UserDefaults (suiteName) for cross-process synchronization.
final class Settings {
    static let shared = Settings()

    static let suiteName = "group.com.nrime.inputmethod"

    private let defaults: UserDefaults

    /// Cached JapaneseKeyConfig to avoid JSON decode on every keystroke.
    /// Invalidated by `reloadJapaneseKeyConfig()` (called when settings change).
    private var _cachedJapaneseKeyConfig: JapaneseKeyConfig?

    private var defaultsObserver: NSObjectProtocol?

    private init() {
        defaults = UserDefaults(suiteName: Settings.suiteName) ?? UserDefaults.standard

        // Invalidate cache when UserDefaults change (e.g., companion app saved settings)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            self?._cachedJapaneseKeyConfig = nil
        }
    }

    // MARK: - Shortcut Keys
    // ShortcutConfig is defined in Shared/SettingsModels.swift

    func shortcut(for key: String) -> ShortcutConfig {
        guard let data = defaults.data(forKey: "shortcut_\(key)"),
              let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else {
            switch key {
            case "toggleEnglish": return .defaultToggleEnglish
            case "toggleNonEnglish": return .defaultToggleNonEnglish
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

    // MARK: - Input Source Recovery

    var preventABCSwitch: Bool {
        get { defaults.bool(forKey: "preventABCSwitch") }
        set { defaults.set(newValue, forKey: "preventABCSwitch") }
    }

    var developerModeEnabled: Bool {
        get { defaults.bool(forKey: "developerModeEnabled") }
        set { defaults.set(newValue, forKey: "developerModeEnabled") }
    }

    var lastNonEnglishMode: InputMode {
        get {
            guard let rawValue = defaults.string(forKey: "lastNonEnglishMode"),
                  let mode = InputMode(rawValue: rawValue),
                  mode != .english else {
                return .korean
            }
            return mode
        }
        set {
            guard newValue != .english else { return }
            defaults.set(newValue.rawValue, forKey: "lastNonEnglishMode")
        }
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

    // MARK: - Japanese IME Keys
    // JapaneseKeyConfig, CapsLockAction, ShiftKeyAction, PunctuationStyle
    // are defined in Shared/SettingsModels.swift

    var japaneseKeyConfig: JapaneseKeyConfig {
        get {
            if let cached = _cachedJapaneseKeyConfig {
                return cached
            }
            guard let data = defaults.data(forKey: "japaneseKeyConfig"),
                  let config = try? JSONDecoder().decode(JapaneseKeyConfig.self, from: data) else {
                let defaultConfig = JapaneseKeyConfig.default
                _cachedJapaneseKeyConfig = defaultConfig
                return defaultConfig
            }
            _cachedJapaneseKeyConfig = config
            return config
        }
        set {
            _cachedJapaneseKeyConfig = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "japaneseKeyConfig")
            }
        }
    }

    /// Reload cached JapaneseKeyConfig from UserDefaults.
    /// Call this when the companion settings app changes config.
    func reloadJapaneseKeyConfig() {
        _cachedJapaneseKeyConfig = nil
    }

}
