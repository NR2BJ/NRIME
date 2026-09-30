import Cocoa
import Combine
import UniformTypeIdentifiers

/// Observable settings store that reads/writes from App Group UserDefaults.
/// Mirrors the Settings class used by the input method process.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init() {
        // Through AppGroupDefaults like every other App Group user: a test or
        // snapshot run (which loads, and so writes back, every setting) must
        // not touch the owner's live configuration.
        defaults = AppGroupDefaults.make()

        _inlineIndicatorEnabled = Published(initialValue: true)
        _indicatorPositionMode = Published(initialValue: "caret")
        _tapThreshold = Published(initialValue: 0.2)
        _preventABCSwitch = Published(initialValue: false)
        _secureInputASCIIFallback = Published(initialValue: true)
        _developerModeEnabled = Published(initialValue: false)
        _toggleEnglishShortcut = Published(initialValue: .defaultToggleEnglish)
        _toggleNonEnglishShortcut = Published(initialValue: .defaultToggleNonEnglish)
        _hanjaConvertShortcut = Published(initialValue: .defaultHanjaConvert)
        _tapHoldBufferingEnabled = Published(initialValue: false)
        _japaneseKeyConfig = Published(initialValue: .default)
        _permissionStatus = Published(initialValue: nil)

        reloadFromDefaults()
    }

    // MARK: - Shortcuts

    @Published var toggleEnglishShortcut: ShortcutConfig {
        didSet { saveShortcut(toggleEnglishShortcut, for: "toggleEnglish") }
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

    @Published var indicatorPositionMode: String {
        didSet { defaults.set(indicatorPositionMode, forKey: "indicatorPositionMode") }
    }

    @Published var secureInputASCIIFallback: Bool {
        didSet { defaults.set(secureInputASCIIFallback, forKey: "secureInputASCIIFallback") }
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

    @Published var tapHoldBufferingEnabled: Bool {
        didSet { defaults.set(tapHoldBufferingEnabled, forKey: "tapHoldBufferingEnabled") }
    }

    // MARK: - Input Method Permissions

    /// What the input method last reported about its own grants. Read-only here.
    @Published private(set) var permissionStatus: PermissionStatus?

    func reloadPermissionStatus() {
        permissionStatus = PermissionStatus.load(from: defaults)
    }

    /// Ask the input method to check again without prompting; the answer
    /// comes back as PermissionStatus.changedNotification.
    func refreshPermissionStatus() {
        reloadPermissionStatus()
        // A test or snapshot run must not set the real input method checking
        // (it answers by writing the owner's App Group).
        if AppGroupDefaults.isRunningTests { return }
        DistributedNotificationCenter.default().postNotificationName(
            PermissionStatus.refreshNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Ask the input method to check again and to request what is missing.
    /// The answer arrives in the shared defaults a moment later.
    func requestPermissionRecheck() {
        DistributedNotificationCenter.default().postNotificationName(
            PermissionStatus.recheckNotification, object: nil, userInfo: nil, deliverImmediately: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.reloadPermissionStatus()
        }
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
        indicatorPositionMode = defaults.string(forKey: "indicatorPositionMode") ?? "caret"

        let tapVal = defaults.double(forKey: "tapThreshold")
        tapThreshold = tapVal > 0 ? tapVal : 0.2
        tapHoldBufferingEnabled = defaults.bool(forKey: "tapHoldBufferingEnabled")
        preventABCSwitch = defaults.bool(forKey: "preventABCSwitch")
        secureInputASCIIFallback = defaults.object(forKey: "secureInputASCIIFallback") == nil
            ? true : defaults.bool(forKey: "secureInputASCIIFallback")
        developerModeEnabled = defaults.bool(forKey: "developerModeEnabled")

        toggleEnglishShortcut = Self.loadShortcut("toggleEnglish", from: defaults) ?? .defaultToggleEnglish
        toggleNonEnglishShortcut = Self.loadShortcut("toggleNonEnglish", from: defaults) ?? .defaultToggleNonEnglish
        hanjaConvertShortcut = Self.loadShortcut("hanjaConvert", from: defaults) ?? .defaultHanjaConvert
        japaneseKeyConfig = Self.loadJapaneseKeyConfig(from: defaults)
        reloadPermissionStatus()
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

// ShortcutConfig, JapaneseKeyConfig, CapsLockAction, PunctuationStyle
// are defined in Shared/SettingsModels.swift (shared between NRIME and NRIMESettings targets)
