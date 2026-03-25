import Cocoa

/// Handles all shortcut detection: modifier-only taps, modifier+key combos, and plain keys.
/// Reads shortcut configurations from Settings.shared.
final class ShortcutHandler {

    /// Action to perform when a shortcut is triggered
    enum Action {
        case toggleEnglish
        case toggleNonEnglish
        case switchKorean
        case switchJapanese
        case hanjaConvert
    }

    /// Set by NRIMEInputController. Returns true to consume the event.
    var onAction: ((Action) -> Bool)?

    /// All shortcut keys and their corresponding actions.
    private static let allShortcuts: [(String, Action)] = [
        ("toggleEnglish", .toggleEnglish),
        ("toggleNonEnglish", .toggleNonEnglish),
        ("switchKorean", .switchKorean),
        ("switchJapanese", .switchJapanese),
        ("hanjaConvert", .hanjaConvert),
    ]

    // Tracking state for modifier-only tap detection
    private var activeModifierKeyCode: UInt16?   // which modifier key is currently held
    private var modifierDownTime: Date?
    private var modifierWasUsedAsCombo = false
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    // Double-Shift tracking for Caps Lock toggle
    private var lastShiftTapTime: Date?
    private var lastShiftTapKeyCode: UInt16?
    private let doubleTapWindow: TimeInterval = 0.3

    /// When true, the active modifier key is registered as a dedicated switch key.
    /// The controller should strip its modifier flag from keyDown events
    /// so the engine receives base characters (e.g., 'ㄱ' not 'ㄲ').
    var shouldStripActiveModifier: Bool {
        guard Settings.shared.dedicatedModifierMode,
              let activeKey = activeModifierKeyCode,
              let flag = ShortcutConfig.modifierFlag(for: activeKey) else {
            return false
        }
        // Check if this modifier is registered as a tap shortcut
        for (key, _) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled, config.isModifierOnlyTap else { continue }
            if config.keyCode == activeKey { return true }
        }
        return false
    }

    /// The modifier flag to strip from events when shouldStripActiveModifier is true.
    var activeModifierFlag: NSEvent.ModifierFlags? {
        guard let activeKey = activeModifierKeyCode else { return nil }
        return ShortcutConfig.modifierFlag(for: activeKey)
    }

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
        guard let flag = ShortcutConfig.modifierFlag(for: keyCode) else {
            // Caps Lock: fires on BOTH press and release. Only trigger on press (capsLock flag SET).
            if keyCode == ShortcutConfig.keyCodeCapsLock {
                let capsNowOn = newFlags.contains(.capsLock)
                let capsWasOn = oldFlags.contains(.capsLock)
                // Only trigger when Caps Lock transitions OFF → ON (press, not release)
                guard capsNowOn && !capsWasOn else { return false }
                // Shift+CapsLock = real Caps Lock, don't intercept
                if newFlags.contains(.shift) { return false }
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
                // Double-Shift tap → toggle Caps Lock
                let isShiftKey = (keyCode == ShortcutConfig.keyCodeLeftShift ||
                                  keyCode == ShortcutConfig.keyCodeRightShift)
                if isShiftKey,
                   let lastTime = lastShiftTapTime,
                   Date().timeIntervalSince(lastTime) < doubleTapWindow {
                    lastShiftTapTime = nil
                    lastShiftTapKeyCode = nil
                    toggleCapsLock()
                    return true
                }
                if isShiftKey {
                    lastShiftTapTime = Date()
                    lastShiftTapKeyCode = keyCode
                }
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
        //    Exception: dedicated modifier mode — the modifier is always a tap, never a combo
        if activeModifierKeyCode != nil && !shouldStripActiveModifier {
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
        for (key, action) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled else { continue }
            if config.isModifierOnlyTap && config.keyCode == keyCode {
                return performAction(action)
            }
        }
        return false
    }

    /// Check modifier+key combo shortcuts. Returns nil if no match, Bool if matched.
    private func checkModifierKeyCombo(_ event: NSEvent) -> Bool? {
        for (key, action) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled, !config.isModifierOnlyTap else { continue }

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

            // For modifier+key combos, high-level flags are sufficient.
            // Don't enforce left/right distinction — Option+Enter should work
            // with either left or right Option key.

            return performAction(action)
        }

        return nil // No match
    }

    /// Check plain-key shortcuts (no modifier, e.g. F13, Caps Lock)
    private func checkPlainKeyShortcut(_ keyCode: UInt16) -> Bool {
        for (key, action) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled, !config.isModifierOnlyTap else { continue }
            guard NSEvent.ModifierFlags(rawValue: UInt(config.modifiers)).isEmpty else { continue }
            if config.keyCode == keyCode {
                return performAction(action)
            }
        }
        return false
    }

    // MARK: - Execute

    private func performAction(_ action: Action) -> Bool {
        DeveloperLogger.shared.log("Shortcut", "Shortcut triggered", metadata: ["action": "\(action)"])
        if let onAction = onAction {
            return onAction(action)
        }
        // Default behavior if no onAction handler is set
        switch action {
        case .toggleEnglish:
            StateManager.shared.toggleEnglish()
        case .toggleNonEnglish:
            StateManager.shared.toggleNonEnglish()
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

    /// Toggle Caps Lock by posting a synthetic key event.
    private func toggleCapsLock() {
        DeveloperLogger.shared.log("Shortcut", "Double-Shift → toggling Caps Lock")
        DispatchQueue.main.async {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x39, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x39, keyDown: false) else { return }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

}
