import ApplicationServices
import Cocoa

/// Checks the input method's own grants and publishes them for the settings
/// app (see PermissionStatus). Asks macOS for a missing grant only when the
/// user presses the button in settings — never on its own.
enum PermissionMonitor {
    private static var lastCheck: Date = .distantPast
    private static var observer: NSObjectProtocol?

    static func start() {
        refresh(force: true)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: PermissionStatus.recheckNotification, object: nil, queue: .main
        ) { _ in
            requestMissing()
            refresh(force: true)
        }
    }

    /// Cheap enough for activation, but throttled to once a minute.
    static func refreshIfStale() {
        refresh(force: false)
    }

    private static func refresh(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastCheck) > 60 else { return }
        lastCheck = now
        let status = PermissionStatus(postEvents: CGPreflightPostEventAccess(),
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
    }

    private static func requestMissing() {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
}
