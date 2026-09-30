import Foundation

/// The input method's permission to post key events and to use accessibility,
/// as the input method itself last saw it.
///
/// A grant belongs to the process that holds it, so only the input method can
/// check its own; it publishes the answer here for the settings app to show.
/// Without this, a lapsed grant is invisible: macOS keeps NRIME listed as
/// allowed while silently dropping every key it posts (see
/// KeyEventReposter.canPostEvents).
struct PermissionStatus: Codable, Equatable {
    var postEvents: Bool
    var accessibility: Bool
    var checkedAt: Date

    static let defaultsKey = "permissionStatus"

    /// Posted by the settings app: check again, and ask for what is missing.
    static let recheckNotification = Notification.Name("com.nrime.inputmethod.recheckPermissions")
    /// Posted by the settings app when it shows the status: check again, without asking.
    static let refreshNotification = Notification.Name("com.nrime.inputmethod.refreshPermissions")
    /// Posted by the input method after it has saved a fresh status.
    static let changedNotification = Notification.Name("com.nrime.inputmethod.permissionsChanged")

    static func load(from defaults: UserDefaults) -> PermissionStatus? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PermissionStatus.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
