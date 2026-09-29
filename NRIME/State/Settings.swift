import Cocoa

/// Shared settings between the input method and Companion App.
/// Uses App Group UserDefaults (suiteName) for cross-process synchronization.
final class Settings {
    static let shared = Settings()

    static let suiteName = AppGroupDefaults.suiteName

    private let defaults: UserDefaults

    /// Cached JapaneseKeyConfig to avoid JSON decode on every keystroke.
    /// Auto-invalidates after 2 seconds so cross-process changes are picked up.
    private var _cachedJapaneseKeyConfig: JapaneseKeyConfig?
    private var _configCacheTime: Date = .distantPast

    private var defaultsObserver: NSObjectProtocol?

    private init() {
        defaults = AppGroupDefaults.make()

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

    // MARK: - Tap-Hold Buffering (fast tap-then-type correction)

    /// When ON, a letter typed while a tap-shortcut modifier is still held is
    /// briefly buffered; the modifier's release timing decides between
    /// "tap + letter in the new mode" and "deliberate shifted letter".
    var tapHoldBufferingEnabled: Bool {
        get { defaults.bool(forKey: "tapHoldBufferingEnabled") }
        set { defaults.set(newValue, forKey: "tapHoldBufferingEnabled") }
    }

    /// Max letter↓→modifier↑ overlap still treated as a tap rollover (seconds).
    var tapOverlapWindow: TimeInterval {
        get {
            let val = defaults.double(forKey: "tapOverlapWindow")
            return val > 0 ? val : 0.05
        }
        set { defaults.set(newValue, forKey: "tapOverlapWindow") }
    }

    // MARK: - Electron Shift+Enter Delay

    /// How long the Electron Shift+Enter newline — and the re-sent ⌘ shortcut
    /// after a commit — waits. 0 means the next turn of the run loop: after
    /// the key being handled, which is what the wait is for.
    var shiftEnterDelay: TimeInterval {
        get { storedDelay("shiftEnterDelay") ?? Self.defaultShiftEnterDelay }
        set { defaults.set(newValue, forKey: "shiftEnterDelay") }
    }

    /// How long the Codex Shift+Enter replay waits after the commit.
    ///
    /// Both defaults were long guesses: 120 ms went in while NRIME could not
    /// post events at all, so no value could have worked. With the permission
    /// back, 10 ms (Codex) and 5 ms (Electron) held up in use (2026-09-30);
    /// the defaults are now no wait, still adjustable while that is tested.
    var codexNewlineDelay: TimeInterval {
        get { storedDelay("codexNewlineDelay") ?? Self.defaultCodexNewlineDelay }
        set { defaults.set(newValue, forKey: "codexNewlineDelay") }
    }

    static let defaultShiftEnterDelay: TimeInterval = 0
    static let defaultCodexNewlineDelay: TimeInterval = 0

    /// A stored delay, including 0 — which used to read as "not set" and
    /// bring back the default.
    private func storedDelay(_ key: String) -> TimeInterval? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return max(0, defaults.double(forKey: key))
    }

    // MARK: - Input Source Recovery

    var preventABCSwitch: Bool {
        get { defaults.bool(forKey: "preventABCSwitch") }
        set { defaults.set(newValue, forKey: "preventABCSwitch") }
    }

    /// While macOS secure input is on, hand the keyboard to a plain ASCII
    /// layout and come back afterwards. Composition is impossible during
    /// secure input anyway, so this keeps password fields typable instead of
    /// showing a Korean/Japanese indicator that no longer reflects reality.
    var secureInputASCIIFallback: Bool {
        get {
            if defaults.object(forKey: "secureInputASCIIFallback") == nil { return true }
            return defaults.bool(forKey: "secureInputASCIIFallback")
        }
        set { defaults.set(newValue, forKey: "secureInputASCIIFallback") }
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

    // MARK: - Permissions

    /// The input method's own grants, published for the settings app.
    var permissionStatus: PermissionStatus? {
        get { PermissionStatus.load(from: defaults) }
        set { newValue?.save(to: defaults) }
    }

    // MARK: - Inline Indicator

    var inlineIndicatorEnabled: Bool {
        get {
            if defaults.object(forKey: "inlineIndicatorEnabled") == nil { return true }
            return defaults.bool(forKey: "inlineIndicatorEnabled")
        }
        set { defaults.set(newValue, forKey: "inlineIndicatorEnabled") }
    }

    /// Indicator position mode: "caret" (input cursor) or "mouse" (mouse cursor).
    var indicatorPositionMode: String {
        get {
            let val = defaults.string(forKey: "indicatorPositionMode")
            return val ?? "caret"
        }
        set { defaults.set(newValue, forKey: "indicatorPositionMode") }
    }

    // MARK: - Japanese IME Keys
    // JapaneseKeyConfig, CapsLockAction, PunctuationStyle
    // are defined in Shared/SettingsModels.swift

    var japaneseKeyConfig: JapaneseKeyConfig {
        get {
            if let cached = _cachedJapaneseKeyConfig,
               Date().timeIntervalSince(_configCacheTime) < 2.0 {
                return cached
            }
            guard let data = defaults.data(forKey: "japaneseKeyConfig"),
                  let config = try? JSONDecoder().decode(JapaneseKeyConfig.self, from: data) else {
                let defaultConfig = JapaneseKeyConfig.default
                _cachedJapaneseKeyConfig = defaultConfig
                return defaultConfig
            }
            _cachedJapaneseKeyConfig = config
            _configCacheTime = Date()
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
