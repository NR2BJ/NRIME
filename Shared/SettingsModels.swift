import Cocoa

// MARK: - Shared Settings Model Types
// These types are used by both the input method (NRIME) and the companion app (NRIMESettings).
// Keeping them in a single file prevents type drift between the two targets.

/// Shortcut configuration for mode switching / hanja conversion.
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

    /// When true, this shortcut is disabled (no key binding assigned)
    var disabled: Bool = false

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
    /// Default: Shift + Space
    static let defaultToggleNonEnglish = ShortcutConfig(
        keyCode: 0x31, modifierKeyCode: keyCodeLeftShift,
        modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
        isModifierOnlyTap: false, label: "Shift + Space"
    )
    /// Default: Option + Enter
    static let defaultHanjaConvert = ShortcutConfig(
        keyCode: 0x24, modifierKeyCode: keyCodeLeftOption,
        modifiers: UInt(NSEvent.ModifierFlags.option.rawValue),
        isModifierOnlyTap: false, label: "Option + Enter"
    )
}

/// Japanese IME key configuration.
///
/// Some fields are retired (see `withRetiredOptionsOff()`): they stay so
/// stored settings and older exports still decode, but are always off.
struct JapaneseKeyConfig: Codable, Equatable {
    /// Retired: F6–F10 conversion keys while composing (hiragana, full/half
    /// katakana, full/half romaji). Always nil.
    var hiraganaKeyCode: UInt16? = nil
    var fullKatakanaKeyCode: UInt16? = nil
    var halfKatakanaKeyCode: UInt16? = nil
    var fullRomajiKeyCode: UInt16? = nil
    var halfRomajiKeyCode: UInt16? = nil

    /// Caps Lock action in Japanese mode
    var capsLockAction: CapsLockAction = .capsLock
    /// Retired: Shift+letter as katakana or romaji. Always .none — Shift
    /// does nothing special; switching to English is the way to type romaji.
    var shiftKeyAction: ShiftKeyAction = .none

    /// Punctuation style: .japanese -> 。、  .fullWidthWestern -> ．，
    var punctuationStyle: PunctuationStyle = .japanese
    /// Whether / key produces ・ (nakaguro)
    var slashToNakaguro: Bool = true
    /// Whether ¥ key produces ¥ (yen sign)
    var yenKeyToYen: Bool = true
    /// Whether Space inserts full-width space (U+3000) instead of half-width (U+0020)
    var fullWidthSpace: Bool = false

    /// Retired: live conversion. Always false.
    var liveConversion: Bool = false
    /// Retired: prediction candidates. Always false.
    var prediction: Bool = false

    /// Candidate panel font size in points (default: 14)
    var candidateFontSize: CGFloat = 14

    /// Conversion trigger keys
    var conversionTriggerSpace: Bool = true
    var conversionTriggerTab: Bool = true
    /// Retired: ↓ as a conversion trigger. Always false (↓ commits, like the
    /// other arrows).
    var conversionTriggerDownArrow: Bool = false

    static let `default` = JapaneseKeyConfig()

    /// This configuration with the retired options forced off.
    ///
    /// Removed from the settings app on 2026-09-29 because the owner does not
    /// use them. Applied wherever a configuration is read, so a stored value
    /// or an imported file cannot quietly turn one back on with no switch
    /// left to turn it off.
    func withRetiredOptionsOff() -> JapaneseKeyConfig {
        var config = self
        config.hiraganaKeyCode = nil
        config.fullKatakanaKeyCode = nil
        config.halfKatakanaKeyCode = nil
        config.fullRomajiKeyCode = nil
        config.halfRomajiKeyCode = nil
        config.shiftKeyAction = .none
        config.liveConversion = false
        config.prediction = false
        config.conversionTriggerDownArrow = false
        return config
    }
}

/// Caps Lock behavior options for Japanese input
enum CapsLockAction: String, Codable, CaseIterable {
    case capsLock = "capsLock"           // System default (toggle caps)
    case katakana = "katakana"           // Convert to full-width katakana
    case romaji = "romaji"               // Convert to half-width romaji
}

/// Shift key behavior options for Japanese input
enum ShiftKeyAction: String, Codable, CaseIterable {
    case none = "none"                   // Normal shift (no special behavior)
    case katakana = "katakana"           // Shift+input -> katakana
    case romaji = "romaji"               // Shift+input -> romaji passthrough
}

/// Punctuation style options for Japanese input
enum PunctuationStyle: String, Codable, CaseIterable {
    case japanese = "japanese"                   // 。、
    case fullWidthWestern = "fullWidthWestern"   // ．，
    case halfWidthWestern = "halfWidthWestern"   // .,
}
