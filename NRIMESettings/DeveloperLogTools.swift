import AppKit
import Foundation

enum DeveloperLogTools {
    private static let suiteName = "group.com.nrime.inputmethod"

    static var logFilePath: String {
        (try? ensureLogFile().path) ?? logDirectoryURL().appendingPathComponent("developer.log").path
    }

    static func openLog() {
        guard let url = try? ensureLogFile() else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func revealLog() {
        guard let url = try? ensureLogFile() else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func clearLog() {
        do {
            let url = try ensureLogFile()
            try headerText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

    @discardableResult
    static func ensureLogFile() throws -> URL {
        let directory = logDirectoryURL()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let logURL = directory.appendingPathComponent("developer.log", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: logURL.path) else {
            return logURL
        }

        try headerText().write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    private static func logDirectoryURL() -> URL {
        DeveloperLogLocation.directoryURL()
    }

    private static func headerText() -> String {
        """
        # NRIME local developer log
        # This file stays on this Mac unless the user shares it manually.
        # Typed text is not recorded automatically.
        # Clear this file anytime from NRIME Settings > General > Developer.

        """
    }
}
