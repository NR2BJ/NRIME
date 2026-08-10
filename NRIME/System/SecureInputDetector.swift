import AppKit
import Carbon
import IOKit

final class SecureInputDetector {
    /// Returns true if the system is in Secure Input mode (e.g., password fields).
    /// Uses Carbon's IsSecureEventInputEnabled() for global detection.
    func isSecureInputActive() -> Bool {
        return IsSecureEventInputEnabled()
    }

    /// Bundle ID of the process that turned secure input on, if it can be
    /// identified.
    ///
    /// The flag itself is process-global and says nothing about who set it or
    /// why. Apps can and do leave it on for hours — a real case had a chat app
    /// holding it all day — so treating "flag is on" as "a password field is
    /// focused right here" locks the user out of composing everywhere.
    func secureInputHolderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        guard let property = IORegistryEntrySearchCFProperty(
            root,
            kIOServicePlane,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ), let sessions = property as? [[String: Any]] else {
            return nil
        }

        for session in sessions {
            if let pid = session["kCGSSessionSecureInputPID"] as? pid_t, pid != 0 {
                return pid
            }
        }
        return nil
    }

    func secureInputHolderBundleID() -> String? {
        guard let pid = secureInputHolderPID() else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Whether the process that claimed secure input is still running.
    /// macOS keeps the claim registered even after that process dies, and the
    /// flag then stays on until logout — observed in the wild.
    static func processIsAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM // exists, we just may not signal it
    }

    /// Whether composition must be suppressed for this keystroke.
    func shouldSuppressComposition() -> Bool {
        guard isSecureInputActive() else { return false }
        let pid = secureInputHolderPID()
        return Self.shouldSuppressComposition(
            holderPID: pid,
            holderIsAlive: pid.map { Self.processIsAlive($0) } ?? false,
            holderBundleID: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    /// Pure decision half of `shouldSuppressComposition()`, for testing.
    ///
    /// Suppress only when a live claimant plausibly owns the field being typed
    /// into. The flag alone cannot carry that judgement: it is process-global,
    /// apps hold it for hours, and it survives the claiming process's death —
    /// a dead claimant leaves it on until logout, which would otherwise disable
    /// Korean and Japanese input for the rest of the session.
    static func shouldSuppressComposition(holderPID: pid_t?,
                                          holderIsAlive: Bool,
                                          holderBundleID: String?,
                                          frontmostBundleID: String?) -> Bool {
        // Registry unreadable: nothing to reason about, so stay careful.
        guard holderPID != nil else { return true }
        // Claim outlived its process — stale, not a focused password field.
        guard holderIsAlive else { return false }
        // Alive but not an app (daemon, helper): cannot be the focused field.
        guard let holderBundleID else { return false }
        if authenticationBundleIDs.contains(holderBundleID) { return true }
        return holderBundleID == frontmostBundleID
    }

    /// Whether secure input is held by the system authentication UI, which is
    /// the only case where stepping the input source aside is warranted.
    func secureInputHeldByAuthenticationUI() -> Bool {
        guard isSecureInputActive(), let holder = secureInputHolderBundleID() else { return false }
        return Self.authenticationBundleIDs.contains(holder)
    }

    /// Bundle IDs of the system authentication UI.
    ///
    /// The secure-input flag can lag the panel actually appearing — measured at
    /// ~2s on this machine — and during that gap the input method would happily
    /// compose into a field that silently drops IME insertions, so the keystroke
    /// disappears. These clients never accept composition, so identify them
    /// directly and pass every key through regardless of the flag.
    private static let authenticationBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
    ]

    /// Whether this client is system authentication UI (admin password prompt,
    /// login window) that must never receive composed text.
    func isAuthenticationClient(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.authenticationBundleIDs.contains(bundleID)
    }
}
