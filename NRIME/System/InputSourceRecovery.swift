import Carbon
import Cocoa

final class InputSourceRecovery {
    static let shared = InputSourceRecovery()

    private var consecutiveRecoveries = 0
    private let maxConsecutiveRecoveries = 3
    private var lastRecoveryTime: Date?
    private var isMonitoring = false
    private var pollTimer: Timer?

    /// Set to true when the user intentionally deactivates NRIME
    /// (e.g., via deactivateServer). Recovery is suppressed while true.
    var userInitiatedSwitch = false

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged(_:)),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        // Fallback: poll every 3 seconds to catch missed notifications (sleep/wake, etc.)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollInputSource()
        }

        // Check immediately after wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NSLog("NRIME: InputSourceRecovery monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        pollTimer?.invalidate()
        pollTimer = nil

        NSLog("NRIME: InputSourceRecovery monitoring stopped")
    }

    @objc private func didWake(_ notification: Notification) {
        // After wake, check with a short delay to let the system settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.pollInputSource()
        }
        // Check again after a longer delay in case the first one was too early
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.pollInputSource()
        }
    }

    private func pollInputSource() {
        guard Settings.shared.preventABCSwitch else { return }
        guard isCurrentSourceNonNRIME() else { return }
        recoverInputSource()
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        // If "Prevent ABC switch" is off, respect user-initiated switches
        if !Settings.shared.preventABCSwitch && userInitiatedSwitch {
            userInitiatedSwitch = false
            return
        }
        userInitiatedSwitch = false

        if isCurrentSourceNonNRIME() {
            recoverInputSource()
        }
    }

    private func isCurrentSourceNonNRIME() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        guard let sourceIDPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return false
        }
        let currentID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
        return !currentID.hasPrefix("com.nrime.inputmethod")
    }

    private func recoverInputSource() {
        let now = Date()

        if let lastTime = lastRecoveryTime, now.timeIntervalSince(lastTime) < 2.0 {
            consecutiveRecoveries += 1
        } else {
            consecutiveRecoveries = 0
        }

        guard consecutiveRecoveries < maxConsecutiveRecoveries else {
            NSLog("NRIME: InputSourceRecovery halted — too many consecutive recoveries (\(consecutiveRecoveries))")
            // Reset after halt so polling can retry later
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.consecutiveRecoveries = 0
                self?.lastRecoveryTime = nil
            }
            return
        }

        lastRecoveryTime = now

        let conditions = [
            kTISPropertyBundleID: "com.nrime.inputmethod.app"
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let nrimeSource = sources.first else {
            NSLog("NRIME: InputSourceRecovery could not find NRIME input source")
            return
        }

        let status = TISSelectInputSource(nrimeSource)
        if status == noErr {
            NSLog("NRIME: Input source recovered successfully")
        } else {
            NSLog("NRIME: Input source recovery failed with status: \(status)")
        }
    }
}
