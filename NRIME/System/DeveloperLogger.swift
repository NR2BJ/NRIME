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

    /// Whether lines are being recorded. Check it before building metadata
    /// that costs anything — a call into the host app, a settings decode.
    var isEnabled: Bool { Settings.shared.developerModeEnabled }

    func log(_ subsystem: String, _ message: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }

        // Stamp the line when it is logged, not when the background queue gets
        // to it: under load the queue runs late, and a lag investigation needs
        // the moment the event was handled. `up` is on the same clock as
        // NSEvent.timestamp, so lines can be lined up against key events.
        let wallClock = Date()
        let uptime = ProcessInfo.processInfo.systemUptime

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let logURL = try Self.ensureLogFile()
                try self.rotateIfNeeded(logURL)

                let line = self.formatLine(
                    subsystem: subsystem,
                    message: message,
                    metadata: metadata,
                    date: wallClock,
                    uptime: uptime
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
        try DeveloperLogLocation.clear(header: headerText())
    }

    static func logFilePath() -> String {
        (try? ensureLogFile().path) ?? logDirectoryURL().appendingPathComponent("developer.log").path
    }

    /// Start over once the file is large, keeping the previous generation as
    /// developer.log.1 so a reproduction just before rotation is not lost.
    private func rotateIfNeeded(_ logURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > maxLogBytes else { return }

        let previous = DeveloperLogLocation.previousFileURL()
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.copyItem(at: logURL, to: previous)

        var header = Self.headerText()
        header += "# Rotated at \(timestampFormatter.string(from: Date()))\n\n"
        try header.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func formatLine(
        subsystem: String,
        message: String,
        metadata: [String: String],
        date: Date,
        uptime: TimeInterval
    ) -> String {
        let timestamp = timestampFormatter.string(from: date)
        var metadata = metadata
        metadata["up"] = String(format: "%.3f", uptime)
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

#if DEBUG
    /// Wait until every line logged so far has been written.
    func drainForTesting() {
        queue.sync {}
    }
#endif

    // MARK: - Main thread stall monitor

    private var stallObservers: [CFRunLoopObserver] = []
    private var iterationStart: TimeInterval = 0

    /// Log main run loop iterations that take longer than `threshold`. Every
    /// key event is handled on this thread, so a long iteration is a stretch
    /// in which typed keys and Shift taps queue up — the "lag" users report.
    /// Measured from waking to the next sleep, so an idle thread records
    /// nothing. The start is stamped before any other wake-up work and the end
    /// after all pre-sleep work (Core Animation commits and the display cycle
    /// run there), so drawing counts too. Costs a clock read per iteration;
    /// logs only when enabled. Iterations under the threshold are not logged:
    /// a Timing line with 30–99 ms of lag and no Stall line is not evidence of
    /// a delay outside this process — check the preceding lines' costMs first.
    func startMainThreadStallMonitor(threshold: TimeInterval = 0.1) {
        guard stallObservers.isEmpty else { return }
        let wake = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min
        ) { [weak self] _, _ in
            self?.iterationStart = ProcessInfo.processInfo.systemUptime
        }
        let sleep = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max
        ) { [weak self] _, _ in
            guard let self, self.iterationStart > 0 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let duration = now - self.iterationStart
            self.iterationStart = 0
            if duration >= threshold, self.isEnabled {
                self.log("MainThread", "Stall", metadata: [
                    "ms": String(format: "%.0f", duration * 1000),
                    "since": String(format: "%.3f", now - duration),
                ])
            }
        }
        for observer in [wake, sleep].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            stallObservers.append(observer)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
