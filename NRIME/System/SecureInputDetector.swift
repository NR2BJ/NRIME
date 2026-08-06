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
    func secureInputHolderBundleID() -> String? {
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
                return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            }
        }
        return nil
    }

    /// Whether composition must be suppressed for this keystroke.
    ///
    /// Suppress when the secure field is plausibly the one being typed into:
    /// the holder is frontmost, or it is the system authentication UI. A
    /// background app holding the flag stale is not a reason to disable the
    /// input method everywhere. When the holder cannot be identified we stay
    /// conservative and suppress, matching the previous behavior.
    func shouldSuppressComposition() -> Bool {
        guard isSecureInputActive() else { return false }
        let holder = secureInputHolderBundleID()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return Self.shouldSuppressComposition(holderBundleID: holder,
                                              frontmostBundleID: frontmost)
    }

    /// Pure decision half of `shouldSuppressComposition()`, for testing.
    static func shouldSuppressComposition(holderBundleID: String?,
                                          frontmostBundleID: String?) -> Bool {
        guard let holderBundleID else { return true } // unknown holder: be safe
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
