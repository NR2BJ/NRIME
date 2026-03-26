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
    private var doubleTapWindow: TimeInterval { Settings.shared.doubleTapWindow }

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
                let matched = checkModifierOnlyTap(keyCode) || checkPlainKeyShortcut(keyCode)
                if matched {
                    // Undo the system Caps Lock toggle so LED stays off
                    toggleCapsLock()
                }
                return matched
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
                // Double-Shift tap → toggle Caps Lock (only for shift keys NOT registered as shortcuts)
                let isShiftKey = (keyCode == ShortcutConfig.keyCodeLeftShift ||
                                  keyCode == ShortcutConfig.keyCodeRightShift)
                let isRegisteredShortcut = isShiftKey && isKeyRegisteredAsShortcut(keyCode)
                if isShiftKey && !isRegisteredShortcut && Settings.shared.shiftDoubleTapEnabled,
                   let lastTime = lastShiftTapTime,
                   lastShiftTapKeyCode == keyCode,
                   Date().timeIntervalSince(lastTime) < doubleTapWindow {
                    lastShiftTapTime = nil
                    lastShiftTapKeyCode = nil
                    toggleCapsLock()
                    return true
                }
                if isShiftKey && !isRegisteredShortcut {
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

    private func isKeyRegisteredAsShortcut(_ keyCode: UInt16) -> Bool {
        for (key, _) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled, config.isModifierOnlyTap else { continue }
            if config.keyCode == keyCode { return true }
        }
        return false
    }

    private func hasAnyModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        return !flags.intersection([.shift, .control, .option, .command]).isEmpty
    }

    /// Track Caps Lock state ourselves since IOHIDGetModifierLockState returns stale values.
    private var capsLockIsOn = false

    /// Toggle Caps Lock using IOKit (no Accessibility permission needed).
    private func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        capsLockIsOn.toggle()
        IOHIDSetModifierLockState(service, Int32(kIOHIDCapsLockState), capsLockIsOn)
        DeveloperLogger.shared.log("Shortcut", "Double-Shift → Caps Lock toggled",
                                   metadata: ["now": "\(capsLockIsOn)"])
    }

}
