import Carbon

final class SecureInputDetector {
    /// Returns true if the system is in Secure Input mode (e.g., password fields).
    /// Uses Carbon's IsSecureEventInputEnabled() for global detection.
    func isSecureInputActive() -> Bool {
        return IsSecureEventInputEnabled()
    }
}
