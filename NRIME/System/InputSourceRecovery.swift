import Carbon
import Cocoa

final class InputSourceRecovery {
    static let shared = InputSourceRecovery()

    private var consecutiveRecoveries = 0
    private let maxConsecutiveRecoveries = 3
    private var lastRecoveryTime: Date?
    private var isMonitoring = false
    private var pollTimer: Timer?
    private let secureInputDetector = SecureInputDetector()
    private let startupRecoveryDelays: [TimeInterval] = [0.5, 2.0, 5.0]

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
        DeveloperLogger.shared.log("InputSourceRecovery", "Monitoring started")
        scheduleStartupRecoveryChecks()
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
        DeveloperLogger.shared.log("InputSourceRecovery", "Monitoring stopped")
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

    private func scheduleStartupRecoveryChecks() {
        guard Settings.shared.preventABCSwitch else { return }

        for delay in startupRecoveryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptStartupRecovery(after: delay)
            }
        }
    }

    private func attemptStartupRecovery(after delay: TimeInterval) {
        let currentSourceIsNonNRIME = isCurrentSourceNonNRIME()
        let secureInputActive = secureInputDetector.isSecureInputActive()
        let shouldRecover = Self.shouldRecoverInputSource(
            preventABCSwitch: Settings.shared.preventABCSwitch,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: currentSourceIsNonNRIME,
            secureInputActive: secureInputActive
        )

        guard shouldRecover else {
            if currentSourceIsNonNRIME || secureInputActive {
                DeveloperLogger.shared.log("InputSourceRecovery", "Startup recovery skipped", metadata: [
                    "delay": String(format: "%.1f", delay),
                    "preventABCSwitch": String(Settings.shared.preventABCSwitch),
                    "secureInput": String(secureInputActive),
                    "sourceIsNonNRIME": String(currentSourceIsNonNRIME)
                ])
            }
            return
        }

        DeveloperLogger.shared.log("InputSourceRecovery", "Startup recovery triggered", metadata: [
            "delay": String(format: "%.1f", delay),
            "sourceIsNonNRIME": String(currentSourceIsNonNRIME)
        ])
        recoverInputSource()
    }

    private func pollInputSource() {
        let currentSourceIsNonNRIME = isCurrentSourceNonNRIME()
        let secureInputActive = secureInputDetector.isSecureInputActive()
        let shouldRecover = Self.shouldRecoverInputSource(
            preventABCSwitch: Settings.shared.preventABCSwitch,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: currentSourceIsNonNRIME,
            secureInputActive: secureInputActive
        )
        guard shouldRecover else { return }

        DeveloperLogger.shared.log("InputSourceRecovery", "Polling triggered recovery", metadata: [
            "preventABCSwitch": String(Settings.shared.preventABCSwitch),
            "secureInput": String(secureInputActive),
            "sourceIsNonNRIME": String(currentSourceIsNonNRIME)
        ])
        recoverInputSource()
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        let currentSourceIsNonNRIME = isCurrentSourceNonNRIME()
        let secureInputActive = secureInputDetector.isSecureInputActive()
        let shouldRecover = Self.shouldRecoverInputSource(
            preventABCSwitch: Settings.shared.preventABCSwitch,
            userInitiatedSwitch: userInitiatedSwitch,
            currentSourceIsNonNRIME: currentSourceIsNonNRIME,
            secureInputActive: secureInputActive
        )

        if shouldRecover || currentSourceIsNonNRIME || userInitiatedSwitch || secureInputActive {
            DeveloperLogger.shared.log("InputSourceRecovery", "Input source changed", metadata: [
                "preventABCSwitch": String(Settings.shared.preventABCSwitch),
                "secureInput": String(secureInputActive),
                "shouldRecover": String(shouldRecover),
                "sourceIsNonNRIME": String(currentSourceIsNonNRIME),
                "userInitiatedSwitch": String(userInitiatedSwitch)
            ])
        }
        userInitiatedSwitch = false

        if shouldRecover {
            recoverInputSource()
        }
    }

    static func shouldRecoverInputSource(
        preventABCSwitch: Bool,
        userInitiatedSwitch: Bool,
        currentSourceIsNonNRIME: Bool,
        secureInputActive: Bool
    ) -> Bool {
        guard !userInitiatedSwitch else { return false }
        guard preventABCSwitch else { return false }
        guard !secureInputActive else { return false }
        return currentSourceIsNonNRIME
    }

    private func isCurrentSourceNonNRIME() -> Bool {
        InputSourceSelector.currentSourceIsNonNRIME()
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
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovery halted", metadata: [
                "consecutiveRecoveries": String(consecutiveRecoveries)
            ])
            // Reset after halt so polling can retry later
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.consecutiveRecoveries = 0
                self?.lastRecoveryTime = nil
            }
            return
        }

        lastRecoveryTime = now

        switch InputSourceSelector.selectVisibleNRIME() {
        case let .success(targetSourceID):
            NSLog("NRIME: Input source recovered successfully")
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovered input source", metadata: [
                "targetSourceID": targetSourceID
            ])
        case let .inputSourceNotFound(targetSourceID):
            NSLog("NRIME: InputSourceRecovery could not find NRIME input source")
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovery failed", metadata: [
                "reason": "input_source_not_found",
                "targetSourceID": targetSourceID
            ])
        case let .enableFailed(targetSourceID, status):
            NSLog("NRIME: Failed to enable NRIME input source during recovery: \(status)")
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovery failed", metadata: [
                "reason": "enable_failed",
                "status": String(status),
                "targetSourceID": targetSourceID
            ])
        case let .selectFailed(targetSourceID, status):
            NSLog("NRIME: Input source recovery failed with status: \(status)")
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovery failed", metadata: [
                "reason": "select_failed",
                "status": String(status),
                "targetSourceID": targetSourceID
            ])
        }
    }
}
