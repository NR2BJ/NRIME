import Foundation

enum LoginRestorePolicy {
    static let stabilizationDuration: TimeInterval = 30.0
    static let pollInterval: TimeInterval = 0.5
    static let terminationGracePeriod: TimeInterval = 1.0

    /// Determine if a restore should be attempted based on current input source.
    /// Treats nil source ID as recoverable (common during early boot / login).
    static func shouldAttemptRestore(
        currentSourceID: String?,
        bundleIDPrefix: String = "com.nrime.inputmethod"
    ) -> Bool {
        guard let currentSourceID else { return true }  // nil = early boot, treat as recoverable
        return !currentSourceID.hasPrefix(bundleIDPrefix)
    }

    static func attemptDelays(
        stabilizationDuration: TimeInterval = stabilizationDuration,
        pollInterval: TimeInterval = pollInterval
    ) -> [TimeInterval] {
        guard stabilizationDuration > 0 else { return [0] }

        let safePollInterval = max(pollInterval, 0.1)
        var delays: [TimeInterval] = [0]
        var nextDelay = safePollInterval

        while nextDelay < stabilizationDuration {
            delays.append(nextDelay)
            nextDelay += safePollInterval
        }

        delays.append(stabilizationDuration)
        return delays
    }
}
