import Cocoa
import Combine
import UniformTypeIdentifiers

/// Observable settings store that reads/writes from App Group UserDefaults.
/// Mirrors the Settings class used by the input method process.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init() {
        let suiteName = "group.com.nrime.inputmethod"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard

        _inlineIndicatorEnabled = Published(initialValue: true)
        _tapThreshold = Published(initialValue: 0.2)
        _preventABCSwitch = Published(initialValue: false)
        _developerModeEnabled = Published(initialValue: false)
        _perAppModeEnabled = Published(initialValue: false)
        _perAppModeType = Published(initialValue: "whitelist")
        _perAppModeList = Published(initialValue: [])
        _toggleEnglishShortcut = Published(initialValue: .defaultToggleEnglish)
        _toggleNonEnglishShortcut = Published(initialValue: .defaultToggleNonEnglish)
        _switchKoreanShortcut = Published(initialValue: .defaultSwitchKorean)
        _switchJapaneseShortcut = Published(initialValue: .defaultSwitchJapanese)
        _hanjaConvertShortcut = Published(initialValue: .defaultHanjaConvert)
        _shiftDoubleTapEnabled = Published(initialValue: true)
        _doubleTapWindow = Published(initialValue: 0.3)
        _shiftEnterDelay = Published(initialValue: 0.015)
        _japaneseKeyConfig = Published(initialValue: .default)

        reloadFromDefaults()
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
    @Published var toggleNonEnglishShortcut: ShortcutConfig {
        didSet { saveShortcut(toggleNonEnglishShortcut, for: "toggleNonEnglish") }
    }
    @Published var hanjaConvertShortcut: ShortcutConfig {
        didSet { saveShortcut(hanjaConvertShortcut, for: "hanjaConvert") }
    }

    // MARK: - General Settings

    @Published var inlineIndicatorEnabled: Bool {
        didSet { defaults.set(inlineIndicatorEnabled, forKey: "inlineIndicatorEnabled") }
    }

    @Published var preventABCSwitch: Bool {
        didSet { defaults.set(preventABCSwitch, forKey: "preventABCSwitch") }
    }

    @Published var developerModeEnabled: Bool {
        didSet { defaults.set(developerModeEnabled, forKey: "developerModeEnabled") }
    }

    @Published var tapThreshold: Double {
        didSet { defaults.set(tapThreshold, forKey: "tapThreshold") }
    }

    @Published var shiftDoubleTapEnabled: Bool {
        didSet { defaults.set(shiftDoubleTapEnabled, forKey: "shiftDoubleTapEnabled") }
    }

    @Published var doubleTapWindow: Double {
        didSet { defaults.set(doubleTapWindow, forKey: "doubleTapWindow") }
    }

    @Published var shiftEnterDelay: Double {
        didSet { defaults.set(shiftEnterDelay, forKey: "shiftEnterDelay") }
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

    // MARK: - Japanese Key Config

    @Published var japaneseKeyConfig: JapaneseKeyConfig {
        didSet { saveJapaneseKeyConfig() }
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

    private static func loadJapaneseKeyConfig(from defaults: UserDefaults) -> JapaneseKeyConfig {
        guard let data = defaults.data(forKey: "japaneseKeyConfig"),
              let config = try? JSONDecoder().decode(JapaneseKeyConfig.self, from: data) else {
            return .default
        }
        return config
    }

    private func saveJapaneseKeyConfig() {
        if let data = try? JSONEncoder().encode(japaneseKeyConfig) {
            defaults.set(data, forKey: "japaneseKeyConfig")
        }
    }

    func reloadFromDefaults() {
        inlineIndicatorEnabled = defaults.object(forKey: "inlineIndicatorEnabled") == nil
            ? true
            : defaults.bool(forKey: "inlineIndicatorEnabled")

        let tapVal = defaults.double(forKey: "tapThreshold")
        tapThreshold = tapVal > 0 ? tapVal : 0.2
        shiftDoubleTapEnabled = defaults.object(forKey: "shiftDoubleTapEnabled") == nil
            ? true : defaults.bool(forKey: "shiftDoubleTapEnabled")
        let dtVal = defaults.double(forKey: "doubleTapWindow")
        doubleTapWindow = dtVal > 0 ? dtVal : 0.3
        let seVal = defaults.double(forKey: "shiftEnterDelay")
        shiftEnterDelay = seVal > 0 ? seVal : 0.015
        preventABCSwitch = defaults.bool(forKey: "preventABCSwitch")
        developerModeEnabled = defaults.bool(forKey: "developerModeEnabled")
        perAppModeEnabled = defaults.bool(forKey: "perAppModeEnabled")
        perAppModeType = defaults.string(forKey: "perAppModeType") ?? "whitelist"
        perAppModeList = defaults.stringArray(forKey: "perAppModeList") ?? []

        toggleEnglishShortcut = Self.loadShortcut("toggleEnglish", from: defaults) ?? .defaultToggleEnglish
        toggleNonEnglishShortcut = Self.loadShortcut("toggleNonEnglish", from: defaults) ?? .defaultToggleNonEnglish
        switchKoreanShortcut = Self.loadShortcut("switchKorean", from: defaults) ?? .defaultSwitchKorean
        switchJapaneseShortcut = Self.loadShortcut("switchJapanese", from: defaults) ?? .defaultSwitchJapanese
        hanjaConvertShortcut = Self.loadShortcut("hanjaConvert", from: defaults) ?? .defaultHanjaConvert
        japaneseKeyConfig = Self.loadJapaneseKeyConfig(from: defaults)
    }

    func exportSettingsInteractively() throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export NRIME Settings"
        panel.message = "Save a JSON backup of your NRIME settings and remembered Hanja candidate priority."
        panel.nameFieldStringValue = "NRIME-Settings-\(bundleVersionString()).json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let snapshot = SettingsTransfer.capture(from: defaults, appVersion: bundleVersionString())
        let data = try SettingsTransfer.encode(snapshot)
        try data.write(to: url, options: .atomic)
        return url
    }

    func importSettingsInteractively() throws -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import NRIME Settings"
        panel.message = "Choose a previously exported NRIME settings JSON file."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let snapshot = try SettingsTransfer.decode(from: data)
        SettingsTransfer.apply(snapshot, to: defaults)
        reloadFromDefaults()
        return url
    }

    private func bundleVersionString() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
    }
}

// ShortcutConfig, JapaneseKeyConfig, CapsLockAction, ShiftKeyAction, PunctuationStyle
// are defined in Shared/SettingsModels.swift (shared between NRIME and NRIMESettings targets)
