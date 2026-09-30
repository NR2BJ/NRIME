import Carbon
import Cocoa

/// Handles all shortcut detection: modifier-only taps, modifier+key combos, and plain keys.
/// Reads shortcut configurations from Settings.shared.
final class ShortcutHandler {

    /// Action to perform when a shortcut is triggered
    enum Action {
        case toggleEnglish
        case toggleNonEnglish
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
        let modifierDownTimestamp: TimeInterval
        /// Whether Shift changes what this key types in the current mode —
        /// decides how quickly Shift must come up for the press to be a tap.
        let shiftMatters: Bool
        var flushWork: DispatchWorkItem
        /// When the timeout found Shift already up and began waiting for its
        /// release event (see flushPendingOnTimeout).
        var waitStartedAt: TimeInterval?
    }
    private var pendingLetter: PendingLetter?

    /// Set by NRIMEInputController: whether a Korean syllable is being composed.
    var isComposingKorean: (() -> Bool)?

    /// How soon after the letter Shift must come up for Shift+letter to be a
    /// tap followed by the letter, where Shift changes the letter (ㄲ ㄸ ㅃ ㅆ
    /// ㅉ ㅒ ㅖ, English capitals). Measured on the owner's typing (2026-09-30,
    /// 104 double consonants): the fastest let go of Shift 47 ms after the
    /// letter, 5% under 54 ms. The old single 50 ms window took about one in
    /// fifty of them for a tap and switched the language.
    static let shiftedLetterTapWindow: TimeInterval = 0.03

    /// The same, where Shift changes nothing (the other Korean keys, every
    /// Japanese letter): Shift has no purpose there but the tap, so the window
    /// is wide. Still bounded, so a Shift held well past the letter is not
    /// read as a tap.
    static let shiftlessLetterTapWindow: TimeInterval = 0.08

    /// Whether Shift changes what this letter key types in `mode`.
    static func shiftMatters(keyCode: UInt16, in mode: InputMode) -> Bool {
        switch mode {
        case .english: return true                 // capitals
        case .japanese: return false               // Shift+letter composes the same kana
        case .korean: return JamoTable.shiftChangesJamo(forKeyCode: keyCode)
        }
    }
    /// event.timestamp of the tracked modifier's press — buffering decisions use
    /// event timestamps (not Date()) so 40ms-scale judgments stay accurate.
    private var modifierDownEventTimestamp: TimeInterval?

    /// All shortcut keys and their corresponding actions.
    private static let allShortcuts: [(String, Action)] = [
        ("toggleEnglish", .toggleEnglish),
        ("toggleNonEnglish", .toggleNonEnglish),
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
    /// The other key of the same pair (the other Shift) was down when the
    /// tracked one was pressed. Cleared if it lets go quickly enough to be
    /// rollover rather than a chord.
    private var twinHeldAtPress = false
    /// Command, Control or Option was already down when the tracked key was
    /// pressed. Cleared if it comes up within `modifierRolloverWindow` — a
    /// shortcut like Cmd+V finishing just as the tap starts.
    private var chordHeldAtPress = false
    /// A clean tap of one Shift that the other Shift interrupted before it came
    /// up: tap to switch, then a capital or ㅆ typed with the other hand. The
    /// second press takes over tracking; this remembers the first so its
    /// release can still count.
    private var twinTapCandidate: (keyCode: UInt16, downTimestamp: TimeInterval)?
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    /// Why the tracked gesture stopped being a solo tap, and when the last key
    /// went down during it. Developer log only — never used to decide.
    private var comboReason: String?
    private var lastKeyDownTimestamp: TimeInterval?

    /// How long one modifier may keep going up after the next one went down
    /// and still be rollover rather than a chord. Its own constant: the tap
    /// buffering windows decide something else and must not retune this one.
    static let modifierRolloverWindow: TimeInterval = 0.05

    /// Hardware key presses the window server has seen, as of the tracked
    /// key's press being handled. A shortcut's third key (Cmd+Shift+Z, and
    /// system hotkeys like Cmd+Shift+4) goes to menus or the system and never
    /// reaches the input method; this count is the only trace it leaves.
    /// A count, not a clock or a live key state.
    private var keyDownCountAtPress: UInt32?

    /// Reads the window server's hardware keyDown count. Replaceable in tests.
    static var hardwareKeyDownCount: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
    }

    /// Distinct per handler (one per controller), so log lines from different
    /// controllers can be told apart. Diagnostics only.
    let diagID: Int = {
        ShortcutHandler.nextDiagID += 1
        return ShortcutHandler.nextDiagID
    }()
    private static var nextDiagID = 0

    /// Consulted only when logging: whether input is going to a password or
    /// authentication field right now, so timing inside it is never recorded.
    var isSensitiveContext: (() -> Bool)?

    /// The latest press of a registered tap key in any controller, and the last
    /// tap that fired. Diagnostics only, written only while logging is on —
    /// never read by a decision.
    private static var lastTapKeyPress: (keyCode: UInt16, timestamp: TimeInterval, ctl: Int)?
    private static var lastFiredTap: (keyCode: UInt16, down: TimeInterval, release: TimeInterval)?

    /// Most recent mouse-button press anywhere, from a global monitor. Kept
    /// process-wide because the monitor is not tied to whichever controller is
    /// tracking a Shift press. Main thread only.
    private static var lastPointerDown: (timestamp: TimeInterval, flags: NSEvent.ModifierFlags)?

    /// Record a mouse-button press. Shift+click is a use of Shift, not a tap:
    /// IMKit never shows the click to the input method, so without this a
    /// quick Shift+click switches the language.
    static func notePointerDown(timestamp: TimeInterval, flags: NSEvent.ModifierFlags) {
        lastPointerDown = (timestamp, flags)
        // A click that belonged to a tap which already fired (its callback ran
        // after the release was handled). Logged so the case can be counted.
        if let tap = lastFiredTap, timestamp >= tap.down, timestamp <= tap.release,
           DeveloperLogger.shared.isEnabled,
           modifierFlags(flags, show: tap.keyCode, flag: .shift) {
            DeveloperLogger.shared.log("Tap", "Late pointer", metadata: [
                "key": keyName(tap.keyCode),
                "beforeReleaseMs": ms(tap.release - timestamp),
            ])
        }
    }

#if DEBUG
    static func resetPointerForTesting() {
        lastPointerDown = nil
        lastFiredTap = nil
        lastTapKeyPress = nil
    }
#endif


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
        twinHeldAtPress = false
        chordHeldAtPress = false
        twinTapCandidate = nil
        keyDownCountAtPress = nil
        comboReason = nil
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

        // Prefer the event's device-dependent bits: the aggregate flag cannot
        // tell the left and right keys apart, so while both are held a release
        // of one looks like nothing changed. Fall back to the aggregate when an
        // event carries no side information (synthetic events).
        let sides = Self.deviceModifierMasks(for: keyCode)
        let sideInfoAvailable = sides.map {
            ((newFlags.rawValue | oldFlags.rawValue) & $0.eitherSide) != 0
        } ?? false

        let isNowDown: Bool
        let wasDown: Bool
        if let sides, sideInfoAvailable {
            isNowDown = (newFlags.rawValue & sides.requiredSide) != 0
            // A flagsChanged event names the key that changed, so with side
            // bits the event alone says which way it went. Comparing with the
            // last flags this controller saw instead breaks once a release is
            // delivered elsewhere (focus moved mid-press — IMKit keeps one
            // controller per client): the next press then looks like "still
            // down", its release is timed from the stale press, reads as a
            // hold, and the tap is lost.
            wasDown = !isNowDown
        } else {
            isNowDown = newFlags.contains(flag)
            wasDown = oldFlags.contains(flag)
        }

        if isNowDown && !wasDown {
            // Another modifier joining while a letter is buffered settles it as
            // a deliberate combo (hold).
            if pendingLetter != nil {
                flushPendingAsHold(reason: "otherModifier")
            }
            // Modifier pressed down — start tracking for potential tap.
            //
            // A gesture that starts with something else already held is a chord,
            // not a solo tap, and must not clear the flag that says so —
            // otherwise Command+Shift, released without a letter, switches the
            // language. The twin key of the same family counts too, unless it
            // turns out to be a rollover (see the twin release below).
            // Read the twin from this event, not from remembered flags, for the
            // same reason as above: a release this controller never saw would
            // otherwise mark every later tap of the other side as a chord.
            let twinAlreadyDown = sides.map {
                (newFlags.rawValue & ($0.eitherSide & ~$0.requiredSide)) != 0
            } ?? false

            // This press takes over tracking. If it interrupts a clean tap of
            // the other Shift, keep that tap so its release still counts.
            // Shift↔Shift only, and only with side bits: across families the
            // overlap is a chord (Cmd+Shift+…), and without side bits the two
            // keys cannot be told apart.
            twinTapCandidate = nil
            if let previous = activeModifierKeyCode, previous != keyCode,
               sideInfoAvailable, let sides,
               Self.deviceModifierMasks(for: previous)?.eitherSide == sides.eitherSide,
               !modifierWasUsedAsCombo, !twinHeldAtPress, !chordHeldAtPress,
               let previousDown = modifierDownEventTimestamp,
               event.timestamp - previousDown < Settings.shared.tapThreshold,
               isKeyRegisteredAsShortcut(previous) {
                twinTapCandidate = (previous, previousDown)
            }
            if DeveloperLogger.shared.isEnabled, !isLoggingRedacted {
                if let previous = activeModifierKeyCode, previous != keyCode,
                   isKeyRegisteredAsShortcut(previous) {
                    logTap("pressOverwrote", key: previous, extra: [
                        "by": Self.keyName(keyCode),
                        "keptAsCandidate": "\(twinTapCandidate != nil)",
                        "prevAgeMs": modifierDownEventTimestamp.map { Self.ms(event.timestamp - $0) } ?? "?",
                    ])
                }
                if isKeyRegisteredAsShortcut(keyCode) {
                    Self.lastTapKeyPress = (keyCode, event.timestamp, diagID)
                }
            }

            activeModifierKeyCode = keyCode
            modifierDownEventTimestamp = event.timestamp
            modifierWasUsedAsCombo = false
            comboReason = nil
            lastKeyDownTimestamp = nil
            chordHeldAtPress = Self.otherModifiersPresent(newFlags, excluding: flag)
            keyDownCountAtPress = chordHeldAtPress ? Self.hardwareKeyDownCount() : nil
            twinHeldAtPress = twinAlreadyDown
            return false // Don't consume yet
        }

        // The Shift whose clean tap the other Shift interrupted, coming up.
        // Settle that tap now; the Shift still down belongs to what is typed
        // next and must not switch again when it comes up.
        if !isNowDown, let candidate = twinTapCandidate, candidate.keyCode == keyCode {
            twinTapCandidate = nil
            let elapsed = event.timestamp - candidate.downTimestamp
            if elapsed >= 0, elapsed < Settings.shared.tapThreshold,
               !Self.otherModifiersPresent(newFlags, excluding: flag),
               !Self.pointerPressed(between: candidate.downTimestamp, and: event.timestamp,
                                    keyCode: keyCode, flag: flag) {
                modifierWasUsedAsCombo = true
                comboReason = "afterTwinTap"
                twinHeldAtPress = false
                if DeveloperLogger.shared.isEnabled {
                    Self.lastFiredTap = (keyCode, candidate.downTimestamp, event.timestamp)
                    logTap("fired", key: keyCode, extra: isLoggingRedacted
                           ? ["via": "twinCandidate", "secure": "Y"]
                           : ["via": "twinCandidate", "elapsedMs": Self.ms(elapsed)])
                }
                return checkModifierOnlyTap(keyCode)
            }
        }

        // The twin of the tracked key coming up. Typing ㅆ or a capital with one
        // Shift and tapping the other to switch overlaps the two briefly; if
        // the first one lets go right after the second went down, that is
        // rollover and the tap still counts. A twin held longer than that was
        // deliberately held with it — a chord.
        if !isNowDown, twinHeldAtPress,
           let active = activeModifierKeyCode, active != keyCode,
           let sides, Self.deviceModifierMasks(for: active)?.eitherSide == sides.eitherSide,
           let downTimestamp = modifierDownEventTimestamp {
            if event.timestamp - downTimestamp < Self.modifierRolloverWindow {
                twinHeldAtPress = false
            } else {
                modifierWasUsedAsCombo = true
                comboReason = "twinHeld"
            }
            return false
        }

        // Command, Control or Option — already down when the tracked key was
        // pressed — coming up. Right after Cmd+V the thumb often leaves Command
        // a moment after Shift goes down; within the rollover window that is
        // not a chord and the tap still counts. Held longer, it was meant as
        // one (Cmd+Shift+…).
        if !isNowDown, chordHeldAtPress,
           let active = activeModifierKeyCode, active != keyCode,
           let activeFlag = ShortcutConfig.modifierFlag(for: active), activeFlag != flag,
           let downTimestamp = modifierDownEventTimestamp {
            if event.timestamp - downTimestamp >= Self.modifierRolloverWindow {
                modifierWasUsedAsCombo = true
                comboReason = "chordHeld"
            } else if !Self.otherModifiersPresent(newFlags, excluding: activeFlag) {
                // A key pressed since the Shift went down that never reached us
                // was the chord's third key (Cmd+Shift+Z went to the menu). The
                // count can only refuse forgiveness, never grant it; under lag
                // it may also count a key typed just after, which errs toward
                // treating the gesture as a chord — the conservative side.
                if let before = keyDownCountAtPress, Self.hardwareKeyDownCount() != before {
                    modifierWasUsedAsCombo = true
                    comboReason = "hiddenKey"
                } else {
                    chordHeldAtPress = false
                }
            }
            return false
        }

        // Release while a letter is buffered: the overlap between letter-down and
        // this release is the discriminating signal. A short overlap means the
        // letter was a rollover after an intended tap (switch mode, replay
        // unshifted); a long one means a deliberate shifted letter. How short
        // depends on whether Shift changes that letter (see the two windows).
        if !isNowDown && wasDown, let pending = pendingLetter, pending.modifierKeyCode == keyCode {
            pending.flushWork.cancel()
            pendingLetter = nil
            let overlap = event.timestamp - pending.letterDownTimestamp
            let hold = event.timestamp - (modifierDownEventTimestamp ?? event.timestamp)
            activeModifierKeyCode = nil
            modifierDownEventTimestamp = nil
            let isTap = overlap < Self.tapWindow(for: pending) && hold < Settings.shared.tapThreshold
            logBufferedLetter(pending, outcome: isTap ? "tap" : "hold", reason: "release",
                              overlap: overlap, hold: hold)
            if isTap {
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
            // Released before the Shift it interrupted: both were held together.
            twinTapCandidate = nil

            // Still holding another modifier means this release ends a chord,
            // not a solo tap.
            let otherStillHeld = Self.otherModifiersPresent(newFlags, excluding: flag)
            let clicked = Self.pointerPressed(between: downTimestamp, and: event.timestamp,
                                              keyCode: keyCode, flag: flag)
            let isTap = !modifierWasUsedAsCombo && !twinHeldAtPress && !chordHeldAtPress
                && !otherStillHeld && !clicked && elapsed < Settings.shared.tapThreshold

            if DeveloperLogger.shared.isEnabled, isKeyRegisteredAsShortcut(keyCode) {
                if isTap { Self.lastFiredTap = (keyCode, downTimestamp, event.timestamp) }
                logTapRelease(key: keyCode, isTap: isTap, elapsed: elapsed, release: event.timestamp,
                              otherStillHeld: otherStillHeld, clicked: clicked)
            }

            if isTap {
                // Solo tap — check modifier-only shortcuts
                return checkModifierOnlyTap(keyCode)
            }
            return false
        }

        // A release this handler was not tracking: the press went to another
        // controller, or another press took over. Logged to tell the cases apart.
        if !isNowDown, wasDown, DeveloperLogger.shared.isEnabled, !isLoggingRedacted,
           isKeyRegisteredAsShortcut(keyCode) {
            var extra = [
                "tracking": activeModifierKeyCode.map(Self.keyName) ?? "none",
                "sideInfo": sideInfoAvailable ? "Y" : "N",
            ]
            // Where this key's press went: another controller (a mismatched
            // pair) or nowhere recent (the press was never delivered).
            if let press = Self.lastTapKeyPress, press.keyCode == keyCode {
                extra["lastPressCtl"] = String(press.ctl)
                extra["lastPressAgeMs"] = Self.ms(event.timestamp - press.timestamp)
            } else {
                extra["lastPressCtl"] = "none"
            }
            logTap("untrackedRelease", key: keyCode, extra: extra)
        }
        return false
    }

    /// Note a keyDown that another part of the controller is consuming.
    ///
    /// Candidate windows and Mozc conversion answer keys before routeEvent runs,
    /// so the handler never sees them and still believes the held modifier is
    /// untouched — releasing it then fires a language switch the user never
    /// asked for. Observation is deliberately separate from matching: this only
    /// records that the gesture used another key.
    func observeConsumedKeyDown(_ event: NSEvent) {
        guard event.type == .keyDown else { return }
        if pendingLetter != nil {
            flushPendingAsHold(reason: "consumedKey")
        }
        twinTapCandidate = nil
        if activeModifierKeyCode != nil {
            modifierWasUsedAsCombo = true
            comboReason = comboReason ?? "consumedKey"
            lastKeyDownTimestamp = event.timestamp
        }
    }

    // MARK: - Key Down

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        // 0. A second key while a letter is buffered settles it as a deliberate
        //    combo (hold). This also covers the stuck case where the modifier's
        //    release event was never delivered (focus change mid-buffer).
        if pendingLetter != nil {
            flushPendingAsHold(reason: "secondKey")
        }
        // A key while both Shifts are down cannot be attributed to either one,
        // so an interrupted tap does not survive it.
        twinTapCandidate = nil

        // 1. Check modifier+key combo shortcuts (any modifier held)
        if let result = checkModifierKeyCombo(event) {
            // Mark modifier as used so tap doesn't fire on release
            modifierWasUsedAsCombo = true
            comboReason = "comboShortcut"
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
            comboReason = comboReason ?? "keyDown"
            lastKeyDownTimestamp = event.timestamp
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
              !chordHeldAtPress,
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
        // A double consonant in the middle of a word is not ambiguous: nobody
        // switches languages halfway through a syllable. It goes straight to
        // the engine, with no wait. (Of the owner's double consonants, 68% came
        // mid-word, among them the five fastest.)
        if StateManager.shared.currentMode == .korean,
           Self.shiftMatters(keyCode: event.keyCode, in: .korean),
           isComposingKorean?() == true {
            return false
        }
        return true
    }

    private static func tapWindow(for pending: PendingLetter) -> TimeInterval {
        pending.shiftMatters ? shiftedLetterTapWindow : shiftlessLetterTapWindow
    }

    private func bufferLetter(_ event: NSEvent) {
        guard let held = activeModifierKeyCode,
              let downTS = modifierDownEventTimestamp else { return }
        let work = DispatchWorkItem { [weak self] in self?.flushPendingOnTimeout() }
        let pending = PendingLetter(event: event,
                                    letterDownTimestamp: event.timestamp,
                                    modifierKeyCode: held,
                                    modifierDownTimestamp: downTS,
                                    shiftMatters: Self.shiftMatters(keyCode: event.keyCode,
                                                                    in: StateManager.shared.currentMode),
                                    flushWork: work)
        pendingLetter = pending
        // The buffer never outlives its tap window, nor the point where the
        // hold itself stops qualifying as a tap.
        let deadline = min(Self.tapWindow(for: pending),
                           (downTS + Settings.shared.tapThreshold) - event.timestamp)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline), execute: work)
    }

    /// Settle the buffered letter as a deliberate shifted keystroke (hold).
    private func flushPendingAsHold(reason: String) {
        guard let pending = pendingLetter else { return }
        pending.flushWork.cancel()
        pendingLetter = nil
        modifierWasUsedAsCombo = true
        comboReason = "bufferedHold"
        logBufferedLetter(pending, outcome: "hold", reason: reason, overlap: nil, hold: nil)
        onReplay?(pending.event, true)
    }

    /// The tap window elapsed. Firing a timer is only evidence that time
    /// passed on *this* thread. If Shift is already physically up, its release
    /// happened and the event is on its way — through the app being typed in,
    /// which lags behind the keyboard whenever the system is busy. So wait for
    /// it and let its own timestamp decide, rather than settle a tap as ㄲ or a
    /// capital because the app was slow. This used to wait 20 ms once: a busy
    /// app took longer, and the tap was lost.
    private func flushPendingOnTimeout() {
        guard var pending = pendingLetter else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if let flag = ShortcutConfig.modifierFlag(for: pending.modifierKeyCode),
           !Self.physicalModifierFlags().contains(flag),
           now - (pending.waitStartedAt ?? now) < Self.releaseWaitLimit {
            pending.flushWork.cancel()
            pending.waitStartedAt = pending.waitStartedAt ?? now
            let work = DispatchWorkItem { [weak self] in self?.flushPendingOnTimeout() }
            pending.flushWork = work
            pendingLetter = pending
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releasePollInterval, execute: work)
            return
        }

        // Still held: a deliberate Shift+letter. Up but no event within the
        // limit: the release went elsewhere (focus moved); settle it.
        flushPendingAsHold(reason: pending.waitStartedAt == nil ? "timeout" : "releaseNotDelivered")
    }

    /// How often, and how long at most, the timeout waits for a release event
    /// that is known to have happened.
    private static let releasePollInterval: TimeInterval = 0.01
    private static let releaseWaitLimit: TimeInterval = 0.5

    /// The modifier keys physically down right now. Replaceable in tests.
    static var physicalModifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }

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
        flushPendingAsHold(reason: "test")
    }

    /// Test seam: the tap window's timer firing now.
    func fireTimeoutForTesting() {
        flushPendingOnTimeout()
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
        case .hanjaConvert:
            return false // Needs engine context, handled elsewhere
        }
        return true
    }

    // MARK: - Helpers

    /// Whether a mouse button went down, with this key held, between the key's
    /// press and release. The window is bounded by event timestamps, so a click
    /// whose monitor callback runs late never blocks a later tap. But only
    /// clicks already recorded when this release is handled can match: if the
    /// main thread stalled and the release is handled before the click's
    /// callback, the tap has already fired, and it is not undone (a commit
    /// cannot be taken back). The "Late pointer" log records that case.
    /// The click's own flags must show this key, so an unrelated click near a
    /// tap does not swallow it. A button already held before the press (a
    /// drag) is not detected — a known limit.
    private static func pointerPressed(between down: TimeInterval, and release: TimeInterval,
                                       keyCode: UInt16, flag: NSEvent.ModifierFlags) -> Bool {
        guard let pointer = lastPointerDown,
              pointer.timestamp >= down, pointer.timestamp <= release else { return false }
        return modifierFlags(pointer.flags, show: keyCode, flag: flag)
    }

    /// Whether these flags show this particular key down: by its side bit when
    /// the flags carry side information, otherwise by the aggregate flag.
    private static func modifierFlags(_ flags: NSEvent.ModifierFlags, show keyCode: UInt16,
                              flag: NSEvent.ModifierFlags) -> Bool {
        if let sides = deviceModifierMasks(for: keyCode),
           (flags.rawValue & sides.eitherSide) != 0 {
            return (flags.rawValue & sides.requiredSide) != 0
        }
        return flags.contains(flag)
    }

    // MARK: - Tap diagnostics (developer log only)

    private static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case ShortcutConfig.keyCodeLeftShift: return "LShift"
        case ShortcutConfig.keyCodeRightShift: return "RShift"
        default: return String(format: "0x%02X", keyCode)
        }
    }

    private static func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.0f", seconds * 1000)
    }

    private func logTap(_ outcome: String, key: UInt16, extra: [String: String] = [:]) {
        var metadata = extra
        metadata["outcome"] = outcome
        metadata["key"] = Self.keyName(key)
        metadata["mode"] = StateManager.shared.currentMode.label
        metadata["ctl"] = String(diagID)
        DeveloperLogger.shared.log("Tap", "Tap decision", metadata: metadata)
    }

    /// One line per buffered letter, naming how it was settled and why, with
    /// the timing the decision used: the data for tuning the two tap windows.
    /// The letter's key code is recorded, never inside a password field.
    private func logBufferedLetter(_ pending: PendingLetter, outcome: String, reason: String,
                                   overlap: TimeInterval?, hold: TimeInterval?) {
        guard DeveloperLogger.shared.isEnabled, !isLoggingRedacted else { return }
        var metadata = [
            "outcome": outcome,
            "reason": reason,
            "key": Self.keyName(pending.modifierKeyCode),
            "letter": String(format: "0x%02X", pending.event.keyCode),
            "mode": StateManager.shared.currentMode.label,
            "shiftMatters": pending.shiftMatters ? "Y" : "N",
            "windowMs": Self.ms(Self.tapWindow(for: pending)),
            "ctl": String(diagID),
            "leadMs": Self.ms(pending.letterDownTimestamp - pending.modifierDownTimestamp),
        ]
        if let overlap { metadata["overlapMs"] = Self.ms(overlap) }
        if let hold { metadata["holdMs"] = Self.ms(hold) }
        // How long the release event took to arrive after Shift was already
        // up: how far the app lagged behind the keyboard.
        if let started = pending.waitStartedAt {
            metadata["waitedMs"] = Self.ms(ProcessInfo.processInfo.systemUptime - started)
        }
        DeveloperLogger.shared.log("Tap", "Buffered letter", metadata: metadata)
    }

    /// Whether log lines must leave out timing: secure input is on, or input
    /// goes to an authentication field (whose flag can lag the panel).
    private var isLoggingRedacted: Bool {
        SecureInputDetector.isSystemSecureInputOn || (isSensitiveContext?() ?? false)
    }

    /// One line per release of a registered tap key, naming what decided it.
    /// Typed characters are never recorded. Inside a password or authentication
    /// field only a switch that fired is logged, with no timing at all — every
    /// line carries its own time, so even a non-firing Shift release would
    /// record when a capital was typed.
    private func logTapRelease(key: UInt16, isTap: Bool, elapsed: TimeInterval, release: TimeInterval,
                               otherStillHeld: Bool, clicked: Bool) {
        if isLoggingRedacted {
            if isTap { logTap("fired", key: key, extra: ["secure": "Y"]) }
            return
        }
        let outcome: String
        if isTap { outcome = "fired" }
        else if modifierWasUsedAsCombo { outcome = "combo" }
        else if twinHeldAtPress { outcome = "twinHeld" }
        else if chordHeldAtPress { outcome = "chordHeld" }
        else if otherStillHeld { outcome = "otherHeld" }
        else if clicked { outcome = "pointer" }
        else { outcome = "tooLong" }

        var extra = ["elapsedMs": Self.ms(elapsed),
                     "thresholdMs": Self.ms(Settings.shared.tapThreshold)]
        if outcome == "combo" {
            extra["reason"] = comboReason ?? "unknown"
            if let keyDown = lastKeyDownTimestamp {
                extra["overlapMs"] = Self.ms(release - keyDown)
            }
        }
        logTap(outcome, key: key, extra: extra)
    }

    /// Whether any significant modifier other than `flag` is present.
    private static func otherModifiersPresent(_ flags: NSEvent.ModifierFlags,
                                              excluding flag: NSEvent.ModifierFlags) -> Bool {
        let significant: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        return !flags.intersection(significant).subtracting(flag).isEmpty
    }

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
