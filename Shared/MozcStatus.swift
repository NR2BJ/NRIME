import Foundation

/// The Mozc engine the input method runs, and a newer one waiting for the
/// next restart — published in the App Group for Settings > About.
struct MozcStatus: Codable, Equatable {
    struct Build: Codable, Equatable {
        let version: String
        /// Upstream commit date, yyyy-MM-dd.
        let date: String
        let commit: String
    }

    var active: Build?
    /// "bundled" (the one in the app) or "downloaded".
    var activeSource: String?
    /// Downloaded; used from the next start of the input method.
    var pending: Build?
    var checkedAt: Date?

    static let defaultsKey = "mozcStatus"

    static func load(from defaults: UserDefaults) -> MozcStatus? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(MozcStatus.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
