import Foundation

/// Where the developer log lives. Shared by the input method (which writes it)
/// and the settings app (which opens and exports it), so the two cannot point
/// at different files.
enum DeveloperLogLocation {
    /// `~/Library/Logs/NRIME` — the standard per-user log location, also shown
    /// by Console.app.
    ///
    /// Not the App Group container: macOS protects group containers from any
    /// process that is not signed by the group's team, and NRIME is ad-hoc
    /// signed, so writes there fail with EPERM. That is how the log silently
    /// stopped in late August 2026 while developer mode was still on.
    static func directoryURL() -> URL {
        // Tests run on the developer's own Mac; keep them out of the real log.
        if AppGroupDefaults.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("NRIME-test-logs", isDirectory: true)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("NRIME", isDirectory: true)
    }

    static func fileURL() -> URL {
        directoryURL().appendingPathComponent("developer.log", isDirectory: false)
    }

    /// The generation kept by rotation.
    static func previousFileURL() -> URL {
        directoryURL().appendingPathComponent("developer.log.1", isDirectory: false)
    }

    /// Empty the log, including the rotated generation — "clear" has to mean
    /// everything the user can no longer see. The current file is rewritten
    /// first so a rotation racing in the input method cannot bring old lines back.
    static func clear(header: String) throws {
        try FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
        try header.write(to: fileURL(), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: previousFileURL())
    }
}
