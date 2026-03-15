import Carbon
import Cocoa

final class InputSourceRecovery {
    static let shared = InputSourceRecovery()

    struct RecoveryThrottleState: Equatable {
        var consecutiveRecoveries: Int
        var lastRecoveryTime: Date?
    }

    enum RecoveryThrottleDecision: Equatable {
        case recover(RecoveryThrottleState)
        case halt(RecoveryThrottleState)
    }

    private let stateQueue = DispatchQueue(label: "com.nrime.inputsource.state")
    private var _userInitiatedSwitch = false
    private var _userInitiatedSwitchExpiresAt: Date?
    private var _consecutiveRecoveries = 0
    private var _lastRecoveryTime: Date?

    private let maxConsecutiveRecoveries = 3
    private let userInitiatedSwitchGracePeriod: TimeInterval = 5.0
    private var isMonitoring = false
    private var pollTimer: Timer?
    private let secureInputDetector = SecureInputDetector()
    private let startupRecoveryDelays: [TimeInterval] = [0.5, 2.0, 5.0]

    /// Set to true when the user intentionally deactivates NRIME
    /// (e.g., via deactivateServer). Recovery is suppressed while true.
    var userInitiatedSwitch: Bool {
        get {
            stateQueue.sync {
                let resolution = Self.resolveUserInitiatedSwitch(
                    now: Date(),
                    isActive: _userInitiatedSwitch,
                    expiresAt: _userInitiatedSwitchExpiresAt
                )
                _userInitiatedSwitch = resolution.isActive
                _userInitiatedSwitchExpiresAt = resolution.expiresAt
                return resolution.isActive
            }
        }
        set {
            stateQueue.sync {
                _userInitiatedSwitch = newValue
                _userInitiatedSwitchExpiresAt = newValue
                    ? Date().addingTimeInterval(userInitiatedSwitchGracePeriod)
                    : nil
            }
        }
    }

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
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
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
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        pollTimer?.invalidate()
        pollTimer = nil

        NSLog("NRIME: InputSourceRecovery monitoring stopped")
        DeveloperLogger.shared.log("InputSourceRecovery", "Monitoring stopped")
    }

    @objc private func didWake(_ notification: Notification) {
        scheduleResumeRecoveryChecks(reason: "did_wake")
    }

    @objc private func screensDidWake(_ notification: Notification) {
        scheduleResumeRecoveryChecks(reason: "screens_did_wake")
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        scheduleResumeRecoveryChecks(reason: "session_did_become_active")
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

    private func pollInputSource(reason: String = "timer", allowUnknownSourceRecovery: Bool = false) {
        let currentSourceID = InputSourceSelector.currentInputSourceID()
        let currentSourceIsNonNRIME = Self.shouldTreatSourceAsRecoverable(
            currentSourceID,
            allowUnknownSourceRecovery: allowUnknownSourceRecovery
        )
        let secureInputActive = secureInputDetector.isSecureInputActive()
        let currentUserInitiatedSwitch = userInitiatedSwitch
        let shouldRecover = Self.shouldRecoverInputSource(
            preventABCSwitch: Settings.shared.preventABCSwitch,
            userInitiatedSwitch: currentUserInitiatedSwitch,
            currentSourceIsNonNRIME: currentSourceIsNonNRIME,
            secureInputActive: secureInputActive
        )
        guard shouldRecover else { return }

        DeveloperLogger.shared.log("InputSourceRecovery", "Polling triggered recovery", metadata: [
            "allowUnknownSourceRecovery": String(allowUnknownSourceRecovery),
            "currentSourceID": currentSourceID ?? "nil",
            "preventABCSwitch": String(Settings.shared.preventABCSwitch),
            "reason": reason,
            "secureInput": String(secureInputActive),
            "sourceIsNonNRIME": String(currentSourceIsNonNRIME)
        ])
        recoverInputSource()
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        let currentSourceIsNonNRIME = isCurrentSourceNonNRIME()
        let secureInputActive = secureInputDetector.isSecureInputActive()
        let currentUserInitiatedSwitch = userInitiatedSwitch
        let shouldRecover = Self.shouldRecoverInputSource(
            preventABCSwitch: Settings.shared.preventABCSwitch,
            userInitiatedSwitch: currentUserInitiatedSwitch,
            currentSourceIsNonNRIME: currentSourceIsNonNRIME,
            secureInputActive: secureInputActive
        )

        if shouldRecover || currentSourceIsNonNRIME || currentUserInitiatedSwitch || secureInputActive {
            DeveloperLogger.shared.log("InputSourceRecovery", "Input source changed", metadata: [
                "preventABCSwitch": String(Settings.shared.preventABCSwitch),
                "secureInput": String(secureInputActive),
                "shouldRecover": String(shouldRecover),
                "sourceIsNonNRIME": String(currentSourceIsNonNRIME),
                "userInitiatedSwitch": String(currentUserInitiatedSwitch)
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
        let throttleDecision = beginRecoveryAttempt(at: now)

        guard case .recover = throttleDecision else {
            let haltedCount: Int
            switch throttleDecision {
            case let .halt(state):
                haltedCount = state.consecutiveRecoveries
            case .recover:
                return
            }
            NSLog("NRIME: InputSourceRecovery halted — too many consecutive recoveries (\(haltedCount))")
            DeveloperLogger.shared.log("InputSourceRecovery", "Recovery halted", metadata: [
                "consecutiveRecoveries": String(haltedCount)
            ])
            // Reset after halt so polling can retry later
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.resetRecoveryThrottle()
            }
            return
        }

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

    private func beginRecoveryAttempt(at now: Date) -> RecoveryThrottleDecision {
        stateQueue.sync {
            let currentState = RecoveryThrottleState(
                consecutiveRecoveries: _consecutiveRecoveries,
                lastRecoveryTime: _lastRecoveryTime
            )
            let decision = Self.evaluateRecoveryThrottle(
                now: now,
                state: currentState,
                maxConsecutiveRecoveries: maxConsecutiveRecoveries
            )
            let nextState: RecoveryThrottleState
            switch decision {
            case let .recover(state), let .halt(state):
                nextState = state
            }
            _consecutiveRecoveries = nextState.consecutiveRecoveries
            _lastRecoveryTime = nextState.lastRecoveryTime
            return decision
        }
    }

    private func resetRecoveryThrottle() {
        stateQueue.sync {
            _consecutiveRecoveries = 0
            _lastRecoveryTime = nil
        }
    }

    static func evaluateRecoveryThrottle(
        now: Date,
        state: RecoveryThrottleState,
        maxConsecutiveRecoveries: Int,
        recoveryWindow: TimeInterval = 2.0
    ) -> RecoveryThrottleDecision {
        var nextState = state
        if let lastTime = state.lastRecoveryTime, now.timeIntervalSince(lastTime) < recoveryWindow {
            nextState.consecutiveRecoveries += 1
        } else {
            nextState.consecutiveRecoveries = 0
        }

        guard nextState.consecutiveRecoveries < maxConsecutiveRecoveries else {
            return .halt(nextState)
        }

        nextState.lastRecoveryTime = now
        return .recover(nextState)
    }

    static func resolveUserInitiatedSwitch(
        now: Date,
        isActive: Bool,
        expiresAt: Date?
    ) -> (isActive: Bool, expiresAt: Date?) {
        guard isActive else { return (false, nil) }
        guard let expiresAt else { return (true, nil) }
        guard expiresAt > now else { return (false, nil) }
        return (true, expiresAt)
    }

    static func shouldTreatSourceAsRecoverable(
        _ currentSourceID: String?,
        allowUnknownSourceRecovery: Bool
    ) -> Bool {
        guard let currentSourceID else { return allowUnknownSourceRecovery }
        return !currentSourceID.hasPrefix(InputSourceSelector.bundleID)
    }

    private func scheduleResumeRecoveryChecks(reason: String) {
        let delays: [TimeInterval] = [0.2, 1.0, 3.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pollInputSource(reason: reason, allowUnknownSourceRecovery: true)
            }
        }
    }
}
