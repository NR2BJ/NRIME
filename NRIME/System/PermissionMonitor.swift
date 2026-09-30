import ApplicationServices
import Cocoa

/// Checks the input method's own grants and publishes them for the settings
/// app (see PermissionStatus). Asks macOS for a missing grant only when the
/// user presses the button in settings — never on its own.
enum PermissionMonitor {
    private static var lastCheck: Date = .distantPast
    private static var observers: [NSObjectProtocol] = []

    /// macOS posts this when any app's Accessibility grant changes — turning
    /// NRIME on or off in System Settings shows up at once, not at the next
    /// activation.
    private static let accessibilityChanged = Notification.Name("com.apple.accessibility.api")

    static func start() {
        refresh(force: true)
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: PermissionStatus.recheckNotification, object: nil, queue: .main
        ) { _ in
            requestMissing()
            refresh(force: true)
        })
        observers.append(center.addObserver(
            forName: PermissionStatus.refreshNotification, object: nil, queue: .main
        ) { _ in
            refresh(force: true)
        })
        observers.append(center.addObserver(
            forName: accessibilityChanged, object: nil, queue: .main
        ) { _ in
            // The new answer can take a moment to reach this process.
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { refresh(force: true) }
            }
        })
    }

    /// Cheap enough for activation, but throttled to once a minute.
    static func refreshIfStale() {
        refresh(force: false)
    }

    private static func refresh(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastCheck) > 60 else { return }
        lastCheck = now
        // canPostEvents, not CGPreflightPostEventAccess alone: that answer is
        // fixed at the first call of the process, so a grant given after
        // launch never showed up (see KeyEventReposter.canPostEvents).
        let status = PermissionStatus(postEvents: KeyEventReposter.canPostEvents,
                                      accessibility: AXIsProcessTrusted(),
                                      checkedAt: now)
        let previous = Settings.shared.permissionStatus
        Settings.shared.permissionStatus = status
        if previous?.postEvents != status.postEvents || previous?.accessibility != status.accessibility {
            DeveloperLogger.shared.log("Permissions", "Status", metadata: [
                "postEvents": "\(status.postEvents)",
                "accessibility": "\(status.accessibility)",
            ])
        }
        DistributedNotificationCenter.default().postNotificationName(
            PermissionStatus.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// The Accessibility prompt adds NRIME to "Device Control and Data Access"
    /// (macOS 27; "Accessibility" before), the grant that also allows posting
    /// events. CGRequestPostEventAccess alone is not enough: like the preflight
    /// it answers from the process's first check and may never reach macOS.
    private static func requestMissing() {
        guard !AXIsProcessTrusted() else { return }
        DeveloperLogger.shared.log("Permissions", "Requesting access")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
    }
}
