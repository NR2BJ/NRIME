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

    /// Set by NRIMEInputController. Called when a buffered letter is resolved:
    /// the event must be routed to the current-mode engine. `keepShift == false`
    /// means the letter belonged to a tap (mode switch already fired) and must be
    /// replayed unshifted into the new mode.
    var onReplay: ((_ event: NSEvent, _ keepShift: Bool) -> Void)?

    /// A letter keyDown that arrived while a tap-registered modifier was still
    /// held. Held back until the modifier release (tap → replay unshifted) or a
    /// timeout/second key (hold → replay shifted) settles the user's intent.
    private struct PendingLetter {
        let event: NSEvent
        let letterDownTimestamp: TimeInterval
        let modifierKeyCode: UInt16
        var flushWork: DispatchWorkItem
        /// Whether the timeout already yielded once to a release still in flight.
        var deferredOnce = false
    }
    private var pendingLetter: PendingLetter?
    /// event.timestamp of the tracked modifier's press — buffering decisions use
    /// event timestamps (not Date()) so 40ms-scale judgments stay accurate.
    private var modifierDownEventTimestamp: TimeInterval?

    /// All shortcut keys and their corresponding actions.
    private static let allShortcuts: [(String, Action)] = [
        ("toggleEnglish", .toggleEnglish),
        ("toggleNonEnglish", .toggleNonEnglish),
        ("switchKorean", .switchKorean),
        ("switchJapanese", .switchJapanese),
        ("hanjaConvert", .hanjaConvert),
    ]

    // Tracking state for modifier-only tap detection.
    //
    // All durations are measured with NSEvent.timestamp — the moment the event
    // actually occurred — never with Date(), which reads the clock when the
    // handler happens to run. The IMKit event thread stalls for hundreds of
    // milliseconds under load (synchronous Mozc IPC, server relaunch sleeps),
    // and a Date()-based measurement charges that stall to the user's key hold:
    // short taps miss the threshold, and long holds processed back-to-back are
    // promoted to taps.
    private var activeModifierKeyCode: UInt16?   // which modifier key is currently held
    private var modifierWasUsedAsCombo = false
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    // Double-Shift tracking for Caps Lock toggle
    private var lastShiftTapTimestamp: TimeInterval?
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
    /// A pending buffered letter is dropped without replay — the client that the
    /// replay would target is going away with the deactivation.
    func reset() {
        if let pending = pendingLetter {
            pending.flushWork.cancel()
            DeveloperLogger.shared.log("Shortcut", "Buffered letter dropped on reset",
                                       metadata: ["keyCode": String(format: "0x%02X", pending.event.keyCode)])
        }
        pendingLetter = nil
        modifierDownEventTimestamp = nil
        activeModifierKeyCode = nil
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
                guard capsNowOn && !capsWasOn else {
                    capsLockIsOn = capsNowOn // observe transitions we don't intercept
                    return false
                }
                // Shift+CapsLock = real Caps Lock, don't intercept
                if newFlags.contains(.shift) {
                    capsLockIsOn = capsNowOn
                    return false
                }
                let matched = checkModifierOnlyTap(keyCode) || checkPlainKeyShortcut(keyCode)
                if matched {
                    // Undo the system Caps Lock toggle: restore the pre-press state.
                    // (toggle-then-apply here would re-assert the ON state the OS
                    // just set, leaving Caps Lock stuck on.)
                    setCapsLock(capsWasOn)
                } else {
                    capsLockIsOn = capsNowOn
                }
                return matched
            }
            return false
        }

        let isNowDown = newFlags.contains(flag)
        let wasDown = oldFlags.contains(flag)

        if isNowDown && !wasDown {
            // Another modifier joining while a letter is buffered settles it as
            // a deliberate combo (hold).
            if pendingLetter != nil {
                flushPendingAsHold()
            }
            // Modifier pressed down — start tracking for potential tap
            activeModifierKeyCode = keyCode
            modifierDownEventTimestamp = event.timestamp
            modifierWasUsedAsCombo = false
            return false // Don't consume yet
        }

        // Release while a letter is buffered: the overlap between letter-down and
        // this release is the discriminating signal. A short overlap means the
        // letter was a rollover after an intended tap (switch mode, replay
        // unshifted); a long one means a deliberate shifted letter.
        if !isNowDown && wasDown, let pending = pendingLetter, pending.modifierKeyCode == keyCode {
            pending.flushWork.cancel()
            pendingLetter = nil
            let overlap = event.timestamp - pending.letterDownTimestamp
            let hold = event.timestamp - (modifierDownEventTimestamp ?? event.timestamp)
            activeModifierKeyCode = nil
            modifierDownEventTimestamp = nil
            // Deliberately skip the double-tap bookkeeping below: a buffer-resolving
            // release is not a clean tap and must not pair into a Caps Lock toggle.
            if overlap < Settings.shared.tapOverlapWindow && hold < Settings.shared.tapThreshold {
                _ = checkModifierOnlyTap(keyCode)
                onReplay?(pending.event, false)
            } else {
                onReplay?(pending.event, true)
            }
            return true
        }

        if !isNowDown && wasDown && activeModifierKeyCode == keyCode {
            // Modifier released — check if it was a solo tap. Measure with the
            // events' own timestamps so a stalled event thread neither hides a
            // real tap nor invents one (see the note on the tracking state).
            guard let downTimestamp = modifierDownEventTimestamp else { return false }
            let elapsed = max(0, event.timestamp - downTimestamp)
            activeModifierKeyCode = nil
            modifierDownEventTimestamp = nil

            if !modifierWasUsedAsCombo && elapsed < Settings.shared.tapThreshold {
                // Double-Shift tap → toggle Caps Lock (only for shift keys NOT registered as shortcuts)
                let isShiftKey = (keyCode == ShortcutConfig.keyCodeLeftShift ||
                                  keyCode == ShortcutConfig.keyCodeRightShift)
                let isRegisteredShortcut = isShiftKey && isKeyRegisteredAsShortcut(keyCode)
                if isShiftKey && !isRegisteredShortcut && Settings.shared.shiftDoubleTapEnabled,
                   let lastTimestamp = lastShiftTapTimestamp,
                   lastShiftTapKeyCode == keyCode,
                   (event.timestamp - lastTimestamp) >= 0,
                   (event.timestamp - lastTimestamp) < doubleTapWindow {
                    lastShiftTapTimestamp = nil
                    lastShiftTapKeyCode = nil
                    toggleCapsLock()
                    return true
                }
                if isShiftKey && !isRegisteredShortcut {
                    lastShiftTapTimestamp = event.timestamp
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

        // 0. A second key while a letter is buffered settles it as a deliberate
        //    combo (hold). This also covers the stuck case where the modifier's
        //    release event was never delivered (focus change mid-buffer).
        if pendingLetter != nil {
            flushPendingAsHold()
        }

        // 1. Check modifier+key combo shortcuts (any modifier held)
        if let result = checkModifierKeyCombo(event) {
            // Mark modifier as used so tap doesn't fire on release
            modifierWasUsedAsCombo = true
            activeModifierKeyCode = nil
            modifierDownEventTimestamp = nil
            return result
        }

        // 1.5. Tap-hold buffering: a letter arriving while a tap-registered
        //      modifier is briefly held is ambiguous (rollover after a tap vs
        //      a deliberate shifted letter). Consume and hold it; the modifier
        //      release or the overlap-window timer settles it.
        if shouldBufferLetter(event) {
            bufferLetter(event)
            return true
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

    // MARK: - Tap-Hold Buffering

    private func shouldBufferLetter(_ event: NSEvent) -> Bool {
        guard Settings.shared.tapHoldBufferingEnabled,
              !event.isARepeat,
              pendingLetter == nil,
              !modifierWasUsedAsCombo,
              let held = activeModifierKeyCode,
              let heldFlag = ShortcutConfig.modifierFlag(for: held),
              event.modifierFlags.contains(heldFlag),
              // Only the ambiguous window right after the modifier went down
              let downTS = modifierDownEventTimestamp,
              event.timestamp - downTS < Settings.shared.tapThreshold,
              // The held modifier must be a tap shortcut, and must not double as
              // a combo modifier (combo users expect combo semantics)
              isKeyRegisteredAsShortcut(held),
              !anyEnabledComboUses(modifierKeyCode: held),
              // Letters only — digits/symbols keep their shifted meanings (！ etc.)
              JamoTable.jamo(forKeyCode: event.keyCode, shifted: false) != nil,
              event.modifierFlags.intersection([.control, .option, .command]).isEmpty,
              onlyHeldSideIsDown(event, held: held)
        else { return false }
        return true
    }

    private func bufferLetter(_ event: NSEvent) {
        guard let held = activeModifierKeyCode,
              let downTS = modifierDownEventTimestamp else { return }
        let work = DispatchWorkItem { [weak self] in self?.flushPendingOnTimeout() }
        pendingLetter = PendingLetter(event: event,
                                      letterDownTimestamp: event.timestamp,
                                      modifierKeyCode: held,
                                      flushWork: work)
        // The buffer never outlives the overlap window, nor the point where the
        // hold itself stops qualifying as a tap.
        let deadline = min(Settings.shared.tapOverlapWindow,
                           (downTS + Settings.shared.tapThreshold) - event.timestamp)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline), execute: work)
    }

    /// Settle the buffered letter as a deliberate shifted keystroke (hold).
    private func flushPendingAsHold() {
        guard let pending = pendingLetter else { return }
        pending.flushWork.cancel()
        pendingLetter = nil
        modifierWasUsedAsCombo = true
        onReplay?(pending.event, true)
    }

    /// The overlap window elapsed. Firing a timer is only evidence that time
    /// passed on *this* thread, which under load can lag far behind the physical
    /// keyboard — so if the modifier is already physically up, its release event
    /// is queued behind whatever stalled us. Yield once so that event decides
    /// with its own timestamp instead of settling a real tap as a capital.
    private func flushPendingOnTimeout() {
        guard var pending = pendingLetter else { return }

        if !pending.deferredOnce,
           let flag = ShortcutConfig.modifierFlag(for: pending.modifierKeyCode),
           !NSEvent.modifierFlags.contains(flag) {
            pending.flushWork.cancel()
            pending.deferredOnce = true
            let work = DispatchWorkItem { [weak self] in self?.flushPendingOnTimeout() }
            pending.flushWork = work
            pendingLetter = pending
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseGracePeriod, execute: work)
            return
        }

        flushPendingAsHold()
    }

    /// How long the timeout waits for an in-flight release before giving up.
    private static let releaseGracePeriod: TimeInterval = 0.02

    /// Whether any enabled modifier+key combo shortcut is bound to this modifier.
    private func anyEnabledComboUses(modifierKeyCode: UInt16) -> Bool {
        for (key, _) in Self.allShortcuts {
            let config = Settings.shared.shortcut(for: key)
            guard !config.disabled, !config.isModifierOnlyTap else { continue }
            if config.modifierKeyCode == modifierKeyCode { return true }
        }
        return false
    }

    /// The event's device-dependent bits must name only the tracked side.
    /// Both shifts down is not a tap gesture; synthetic events without device
    /// bits fall back to trusting the tracked keyCode.
    private func onlyHeldSideIsDown(_ event: NSEvent, held: UInt16) -> Bool {
        guard let sides = Self.deviceModifierMasks(for: held) else { return false }
        let sideBits = event.modifierFlags.rawValue & sides.eitherSide
        if sideBits != 0 {
            return sideBits == sides.requiredSide
        }
        return true
    }

#if DEBUG
    /// Test seam: fire the overlap-window timeout synchronously.
    func flushPendingForTesting() {
        flushPendingAsHold()
    }

    var hasPendingLetterForTesting: Bool { pendingLetter != nil }
#endif

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

            // Check modifier flags match, including left/right distinction.
            // Use device-independent flags for high-level match, then check
            // specific side flags if the shortcut was recorded with a side-specific modifier.
            let significantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let eventSignificant = event.modifierFlags.intersection(significantFlags)
            let requiredSignificant = requiredFlags.intersection(significantFlags)

            guard eventSignificant == requiredSignificant else { continue }

            // Left/right distinction. Prefer the device-dependent modifier bits
            // carried by the event itself: they are present on every real keyDown
            // and stay correct even when no flagsChanged was seen for this press.
            // activeModifierKeyCode is only a fallback (synthetic events carry no
            // device bits), and when neither source can name the side we decline
            // the shortcut — assuming it matched would hijack ordinary typing such
            // as Shift+1 for ！ in Japanese mode.
            if config.modifierKeyCode != 0,
               let sides = Self.deviceModifierMasks(for: config.modifierKeyCode) {
                let rawFlags = event.modifierFlags.rawValue
                if rawFlags & sides.eitherSide != 0 {
                    guard rawFlags & sides.requiredSide != 0 else { continue }
                } else if let activeModifier = activeModifierKeyCode {
                    guard config.modifierKeyCode == activeModifier else { continue }
                } else {
                    continue
                }
            }

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

    /// Device-dependent modifier bits (IOLLEvent.h NX_DEVICE*KEYMASK) for a physical
    /// modifier keyCode: the bit for that exact key, plus the bits for both sides so
    /// callers can tell "side is known" from "side is unavailable".
    private static func deviceModifierMasks(
        for modifierKeyCode: UInt16
    ) -> (requiredSide: UInt, eitherSide: UInt)? {
        let leftShift: UInt  = 0x0000_0002
        let rightShift: UInt = 0x0000_0004
        let leftCtrl: UInt   = 0x0000_0001
        let rightCtrl: UInt  = 0x0000_2000
        let leftOption: UInt  = 0x0000_0020
        let rightOption: UInt = 0x0000_0040
        let leftCommand: UInt  = 0x0000_0008
        let rightCommand: UInt = 0x0000_0010

        switch modifierKeyCode {
        case ShortcutConfig.keyCodeLeftShift:
            return (leftShift, leftShift | rightShift)
        case ShortcutConfig.keyCodeRightShift:
            return (rightShift, leftShift | rightShift)
        case ShortcutConfig.keyCodeLeftCtrl:
            return (leftCtrl, leftCtrl | rightCtrl)
        case ShortcutConfig.keyCodeRightCtrl:
            return (rightCtrl, leftCtrl | rightCtrl)
        case ShortcutConfig.keyCodeLeftOption:
            return (leftOption, leftOption | rightOption)
        case ShortcutConfig.keyCodeRightOption:
            return (rightOption, leftOption | rightOption)
        case ShortcutConfig.keyCodeLeftCmd:
            return (leftCommand, leftCommand | rightCommand)
        case ShortcutConfig.keyCodeRightCmd:
            return (rightCommand, leftCommand | rightCommand)
        default:
            return nil
        }
    }

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

    /// Toggle Caps Lock using IOKit (double-Shift-tap path).
    private func toggleCapsLock() {
        setCapsLock(!capsLockIsOn)
    }

    /// Set Caps Lock to an explicit state using IOKit (no Accessibility permission needed).
    private func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        capsLockIsOn = on
        IOHIDSetModifierLockState(service, Int32(kIOHIDCapsLockState), on)
        DeveloperLogger.shared.log("Shortcut", "Caps Lock state set",
                                   metadata: ["now": "\(on)"])
    }

}
