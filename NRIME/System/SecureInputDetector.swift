import Carbon

final class SecureInputDetector {
    /// Returns true if the system is in Secure Input mode (e.g., password fields).
    /// Uses Carbon's IsSecureEventInputEnabled() for global detection.
    func isSecureInputActive() -> Bool {
        return IsSecureEventInputEnabled()
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
