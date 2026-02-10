import Cocoa

final class ShortcutHandler {
    /// Tap threshold in seconds. Only applies to modifier-only shortcuts.
    var tapThreshold: TimeInterval = 0.2

    private var rightShiftDownTime: Date?
    private var rightShiftWasUsedAsModifier = false
    private var previousModifierFlags: NSEvent.ModifierFlags = []

    // Right Shift keyCode = 0x3C, Left Shift = 0x38
    private let rightShiftKeyCode: UInt16 = 0x3C

    /// Process an event for shortcut detection.
    /// Returns true if the event was consumed as a shortcut action.
    func handleEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDownForModifierTracking(event)
        default:
            return false
        }
    }

    /// Reset internal state (e.g., on deactivateServer).
    func reset() {
        rightShiftDownTime = nil
        rightShiftWasUsedAsModifier = false
        previousModifierFlags = []
    }

    // MARK: - Private

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let isRightShift = event.keyCode == rightShiftKeyCode
        let shiftIsNowDown = event.modifierFlags.contains(.shift)
        let shiftWasDown = previousModifierFlags.contains(.shift)

        defer { previousModifierFlags = event.modifierFlags }

        guard isRightShift else { return false }

        if shiftIsNowDown && !shiftWasDown {
            // Right Shift pressed down
            rightShiftDownTime = Date()
            rightShiftWasUsedAsModifier = false
            return false // Don't consume — might be Shift+key combo
        }

        if !shiftIsNowDown && shiftWasDown {
            // Right Shift released
            guard let downTime = rightShiftDownTime else { return false }
            let elapsed = Date().timeIntervalSince(downTime)
            rightShiftDownTime = nil

            if !rightShiftWasUsedAsModifier && elapsed < tapThreshold {
                // Solo tap detected — toggle English
                StateManager.shared.toggleEnglish()
                return true
            }
        }

        return false
    }

    private func handleKeyDownForModifierTracking(_ event: NSEvent) -> Bool {
        // If Right Shift is held and another key is pressed,
        // mark it as "used as modifier" to prevent false tap detection
        if rightShiftDownTime != nil {
            rightShiftWasUsedAsModifier = true
        }
        return false // Never consume keyDown here
    }
}
