import Cocoa

final class DeveloperLogger {
    static let shared = DeveloperLogger()

    private let queue = DispatchQueue(label: "com.nrime.inputmethod.developer-log", qos: .utility)
    private let maxLogBytes = 512 * 1024

    private lazy var timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    func log(_ subsystem: String, _ message: String, metadata: [String: String] = [:]) {
        guard Settings.shared.developerModeEnabled else { return }

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let logURL = try Self.ensureLogFile()
                try self.rotateIfNeeded(logURL)

                let line = self.formatLine(
                    subsystem: subsystem,
                    message: message,
                    metadata: metadata
                )
                guard let data = line.data(using: .utf8) else { return }

                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } catch {
                NSLog("NRIME: DeveloperLogger failed: \(error)")
            }
        }
    }

    static func ensureLogFile() throws -> URL {
        let logDirectory = try ensureLogDirectory()
        let logURL = logDirectory.appendingPathComponent("developer.log", isDirectory: false)

        guard !FileManager.default.fileExists(atPath: logURL.path) else {
            return logURL
        }

        try headerText().write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    static func clearLog() throws {
        let logURL = try ensureLogFile()
        try headerText().write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func logFilePath() -> String {
        (try? ensureLogFile().path) ?? logDirectoryURL().appendingPathComponent("developer.log").path
    }

    private func rotateIfNeeded(_ logURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > maxLogBytes else { return }

        var header = Self.headerText()
        header += "# Rotated at \(timestampFormatter.string(from: Date()))\n\n"
        try header.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func formatLine(
        subsystem: String,
        message: String,
        metadata: [String: String]
    ) -> String {
        let timestamp = timestampFormatter.string(from: Date())
        let normalizedMessage = Self.normalize(message)
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\(Self.normalize($0.key))=\(Self.normalize($0.value))" }
            .joined(separator: " ")

        if metadataText.isEmpty {
            return "[\(timestamp)] [\(subsystem)] \(normalizedMessage)\n"
        }
        return "[\(timestamp)] [\(subsystem)] \(normalizedMessage) | \(metadataText)\n"
    }

    private static func ensureLogDirectory() throws -> URL {
        let directory = logDirectoryURL()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func logDirectoryURL() -> URL {
        let fileManager = FileManager.default

        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Settings.suiteName
        ) {
            return containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("NRIME", isDirectory: true)
        }

        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return appSupportURL
            .appendingPathComponent("NRIME", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private static func headerText() -> String {
        """
        # NRIME local developer log
        # This file stays on this Mac unless the user shares it manually.
        # Typed text is not recorded automatically.
        # Clear this file anytime from NRIME Settings > General > Developer.

        """
    }

    // MARK: - Detailed Key Logging

    /// Log a key event with full detail (keyCode, modifiers, characters).
    /// Only logs when both developerMode AND detailedKeyLogging are enabled.
    func logKeyEvent(_ subsystem: String, _ message: String, event: NSEvent) {
        guard Settings.shared.detailedKeyLoggingEnabled else { return }
        log(subsystem, message, metadata: [
            "keyCode": String(format: "0x%02X", event.keyCode),
            "modifiers": String(format: "0x%08X", event.modifierFlags.rawValue),
            "chars": event.characters ?? "",
            "charsIgnoring": event.charactersIgnoringModifiers ?? ""
        ])
    }

    /// Log a selector forwarding event.
    /// Only logs when both developerMode AND detailedKeyLogging are enabled.
    func logSelector(_ subsystem: String, _ message: String, selector: String) {
        guard Settings.shared.detailedKeyLoggingEnabled else { return }
        log(subsystem, message, metadata: [
            "selector": selector
        ])
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
