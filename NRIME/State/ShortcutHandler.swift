import Cocoa

/// Handles all shortcut detection: modifier-only taps, modifier+key combos, and plain keys.
/// Reads shortcut configurations from Settings.shared.
final class ShortcutHandler {

    /// Action to perform when a shortcut is triggered
    enum Action {
        case toggleEnglish
        case switchKorean
        case switchJapanese
        case hanjaConvert
    }

    /// Set by NRIMEInputController. Returns true to consume the event.
    var onAction: ((Action) -> Bool)?

    // Tracking state for modifier-only tap detection
    private var activeModifierKeyCode: UInt16?   // which modifier key is currently held
    private var modifierDownTime: Date?
    private var modifierWasUsedAsCombo = false
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    /// Process an event for shortcut detection.
    /// Returns true if the event was consumed as a shortcut action.
    func handleEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return false
        }
    }

    /// Reset internal state (e.g., on deactivateServer).
    func reset() {
        activeModifierKeyCode = nil
        modifierDownTime = nil
        modifierWasUsedAsCombo = false
        previousModifierFlags = []
    }

    // MARK: - Flags Changed (modifier key press/release)

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let newFlags = event.modifierFlags
        let oldFlags = previousModifierFlags
        defer { previousModifierFlags = newFlags }

        // Determine if this modifier key went down or up
        guard let flag = Settings.ShortcutConfig.modifierFlag(for: keyCode) else {
            // Caps Lock: try modifier-only tap first, then plain-key shortcut
            if keyCode == Settings.ShortcutConfig.keyCodeCapsLock {
                if checkModifierOnlyTap(keyCode) { return true }
                return checkPlainKeyShortcut(keyCode)
            }
            return false
        }

        let isNowDown = newFlags.contains(flag)
        let wasDown = oldFlags.contains(flag)

        if isNowDown && !wasDown {
            // Modifier pressed down — start tracking for potential tap
            activeModifierKeyCode = keyCode
            modifierDownTime = Date()
            modifierWasUsedAsCombo = false
            return false // Don't consume yet
        }

        if !isNowDown && wasDown && activeModifierKeyCode == keyCode {
            // Modifier released — check if it was a solo tap
            guard let downTime = modifierDownTime else { return false }
            let elapsed = Date().timeIntervalSince(downTime)
            activeModifierKeyCode = nil
            modifierDownTime = nil

            if !modifierWasUsedAsCombo && elapsed < Settings.shared.tapThreshold {
                // Solo tap — check modifier-only shortcuts
                return checkModifierOnlyTap(keyCode)
            }
        }

        return false
    }

    // MARK: - Key Down

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        // 1. Check modifier+key combo shortcuts (any modifier held)
        if let result = checkModifierKeyCombo(event) {
            // Mark modifier as used so tap doesn't fire on release
            modifierWasUsedAsCombo = true
            activeModifierKeyCode = nil
            modifierDownTime = nil
            return result
        }

        // 2. If a modifier is held for tap tracking, mark it as used
        if activeModifierKeyCode != nil {
            modifierWasUsedAsCombo = true
        }

        // 3. Check plain-key shortcuts (no modifier required, e.g. F13)
        if !hasAnyModifier(event.modifierFlags) {
            return checkPlainKeyShortcut(keyCode)
        }

        return false
    }

    // MARK: - Shortcut Matching

    /// Check all modifier-only tap shortcuts
    private func checkModifierOnlyTap(_ keyCode: UInt16) -> Bool {
        let shortcuts: [(String, Action)] = [
            ("toggleEnglish", .toggleEnglish),
            ("switchKorean", .switchKorean),
            ("switchJapanese", .switchJapanese),
            ("hanjaConvert", .hanjaConvert),
        ]

        for (key, action) in shortcuts {
            let config = Settings.shared.shortcut(for: key)
            if config.isModifierOnlyTap && config.keyCode == keyCode {
                return performAction(action)
            }
        }
        return false
    }

    /// Check modifier+key combo shortcuts. Returns nil if no match, Bool if matched.
    private func checkModifierKeyCombo(_ event: NSEvent) -> Bool? {
        let shortcuts: [(String, Action)] = [
            ("toggleEnglish", .toggleEnglish),
            ("switchKorean", .switchKorean),
            ("switchJapanese", .switchJapanese),
            ("hanjaConvert", .hanjaConvert),
        ]

        for (key, action) in shortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.isModifierOnlyTap else { continue }

            // Must have a modifier
            let requiredFlags = NSEvent.ModifierFlags(rawValue: UInt(config.modifiers))
            guard !requiredFlags.isEmpty else { continue }

            // Check key matches
            guard event.keyCode == config.keyCode else { continue }

            // Check high-level modifier flags match
            let significantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let eventSignificant = event.modifierFlags.intersection(significantFlags)
            let requiredSignificant = requiredFlags.intersection(significantFlags)
            guard eventSignificant == requiredSignificant else { continue }

            // Check left/right distinction via modifier keyCode
            if let activeModKey = activeModifierKeyCode {
                // We know exactly which physical modifier key is held
                if activeModKey != config.modifierKeyCode { continue }
            }
            // If no activeModifierKeyCode (modifier was already held before we started tracking),
            // fall through and match on high-level flags only

            return performAction(action)
        }

        return nil // No match
    }

    /// Check plain-key shortcuts (no modifier, e.g. F13, Caps Lock)
    private func checkPlainKeyShortcut(_ keyCode: UInt16) -> Bool {
        let shortcuts: [(String, Action)] = [
            ("toggleEnglish", .toggleEnglish),
            ("switchKorean", .switchKorean),
            ("switchJapanese", .switchJapanese),
            ("hanjaConvert", .hanjaConvert),
        ]

        for (key, action) in shortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.isModifierOnlyTap else { continue }
            guard NSEvent.ModifierFlags(rawValue: UInt(config.modifiers)).isEmpty else { continue }
            if config.keyCode == keyCode {
                return performAction(action)
            }
        }
        return false
    }

    // MARK: - Execute

    private func performAction(_ action: Action) -> Bool {
        if let onAction = onAction {
            return onAction(action)
        }
        // Default behavior if no onAction handler is set
        switch action {
        case .toggleEnglish:
            StateManager.shared.toggleEnglish()
        case .switchKorean:
            StateManager.shared.switchTo(.korean)
        case .switchJapanese:
            StateManager.shared.switchTo(.japanese)
        case .hanjaConvert:
            return false // Needs engine context, handled elsewhere
        }
        return true
    }

    // MARK: - Helpers

    private func hasAnyModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        return !flags.intersection([.shift, .control, .option, .command]).isEmpty
    }
}
