import AppKit
import Carbon
import Foundation

final class LoginRestoreController {
    private enum Constants {
        static let suiteName = "group.com.nrime.inputmethod"
        static let preventABCSwitchKey = "preventABCSwitch"
    }

    private let defaults = UserDefaults(suiteName: Constants.suiteName) ?? .standard
    private var scheduledAttempts: [DispatchWorkItem] = []
    private var hasStartedMonitoring = false

    func start() {
        let shouldRestore = defaults.bool(forKey: Constants.preventABCSwitchKey)
        RestoreHelperLogger.log("Login restore helper started", metadata: [
            "preventABCSwitch": String(shouldRestore),
            "pollInterval": Self.delayString(LoginRestorePolicy.pollInterval),
            "stabilizationDuration": Self.delayString(LoginRestorePolicy.stabilizationDuration)
        ])

        guard shouldRestore else {
            terminate(after: 0.2)
            return
        }

        startMonitoring()

        for delay in LoginRestorePolicy.attemptDelays() {
            scheduleAttempt(after: delay, trigger: "scheduled")
        }

        terminate(after: LoginRestorePolicy.stabilizationDuration + LoginRestorePolicy.terminationGracePeriod)
    }

    private func scheduleAttempt(after delay: TimeInterval, trigger: String, bundleID: String? = nil) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptRestore(after: delay, trigger: trigger, bundleID: bundleID)
        }
        scheduledAttempts.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startMonitoring() {
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged(_:)),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        attemptRestore(after: 0, trigger: "input_source_changed")
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        let bundleID = bundleID(from: notification)
        scheduleAttempt(after: 0.1, trigger: "application_launched", bundleID: bundleID)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        let bundleID = bundleID(from: notification)
        scheduleAttempt(after: 0.1, trigger: "application_activated", bundleID: bundleID)
    }

    private func bundleID(from notification: Notification) -> String? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    private func attemptRestore(after delay: TimeInterval, trigger: String, bundleID: String? = nil) {
        let rawSourceID = InputSourceSelector.currentInputSourceID()
        let currentSourceID = rawSourceID ?? "unknown"
        guard LoginRestorePolicy.shouldAttemptRestore(currentSourceID: rawSourceID) else {
            if trigger != "scheduled" || delay == 0 || delay == LoginRestorePolicy.stabilizationDuration {
                var metadata = [
                    "delay": Self.delayString(delay),
                    "currentSourceID": currentSourceID,
                    "trigger": trigger
                ]
                if let bundleID {
                    metadata["bundleID"] = bundleID
                }
                RestoreHelperLogger.log("Login restore skipped", metadata: metadata)
            }
            return
        }

        let result = InputSourceSelector.selectVisibleNRIME()
        switch result {
        case let .success(targetSourceID):
            var metadata = [
                "delay": Self.delayString(delay),
                "currentSourceID": currentSourceID,
                "targetSourceID": targetSourceID,
                "trigger": trigger
            ]
            if let bundleID {
                metadata["bundleID"] = bundleID
            }
            RestoreHelperLogger.log("Login restore succeeded", metadata: metadata)
        case let .inputSourceNotFound(targetSourceID):
            var metadata = [
                "delay": Self.delayString(delay),
                "currentSourceID": currentSourceID,
                "reason": "input_source_not_found",
                "targetSourceID": targetSourceID,
                "trigger": trigger
            ]
            if let bundleID {
                metadata["bundleID"] = bundleID
            }
            RestoreHelperLogger.log("Login restore failed", metadata: metadata)
        case let .enableFailed(targetSourceID, status):
            var metadata = [
                "delay": Self.delayString(delay),
                "currentSourceID": currentSourceID,
                "reason": "enable_failed",
                "status": String(status),
                "targetSourceID": targetSourceID,
                "trigger": trigger
            ]
            if let bundleID {
                metadata["bundleID"] = bundleID
            }
            RestoreHelperLogger.log("Login restore failed", metadata: metadata)
        case let .selectFailed(targetSourceID, status):
            var metadata = [
                "delay": Self.delayString(delay),
                "currentSourceID": currentSourceID,
                "reason": "select_failed",
                "status": String(status),
                "targetSourceID": targetSourceID,
                "trigger": trigger
            ]
            if let bundleID {
                metadata["bundleID"] = bundleID
            }
            RestoreHelperLogger.log("Login restore failed", metadata: metadata)
        }
    }

    private func terminate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.scheduledAttempts.forEach { $0.cancel() }
            self.scheduledAttempts.removeAll()
            DistributedNotificationCenter.default().removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NSApp.terminate(nil)
        }
    }

    private static func delayString(_ delay: TimeInterval) -> String {
        String(format: "%.1f", delay)
    }
}

private enum RestoreHelperLogger {
    private static let queue = DispatchQueue(label: "com.nrime.restorehelper.log", qos: .utility)
    private static let suiteName = "group.com.nrime.inputmethod"
    private static let developerModeEnabledKey = "developerModeEnabled"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String, metadata: [String: String] = [:]) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard defaults.bool(forKey: developerModeEnabledKey) else { return }

        queue.async {
            do {
                let logURL = try ensureLogFile()
                let line = formatLine(message: message, metadata: metadata)
                guard let data = line.data(using: .utf8) else { return }

                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } catch {
                NSLog("NRIME RestoreHelper: logging failed: \(error)")
            }
        }
    }

    private static func ensureLogFile() throws -> URL {
        let directory = try ensureLogDirectory()
        let logURL = directory.appendingPathComponent("developer.log", isDirectory: false)

        guard !FileManager.default.fileExists(atPath: logURL.path) else {
            return logURL
        }

        try headerText().write(to: logURL, atomically: true, encoding: .utf8)
        return logURL
    }

    private static func ensureLogDirectory() throws -> URL {
        let directory = logDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func logDirectoryURL() -> URL {
        let fileManager = FileManager.default

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            return containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("NRIME", isDirectory: true)
        }

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return appSupportURL
            .appendingPathComponent("NRIME", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private static func formatLine(message: String, metadata: [String: String]) -> String {
        let timestamp = timestampFormatter.string(from: Date())
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\(normalize($0.key))=\(normalize($0.value))" }
            .joined(separator: " ")

        if metadataText.isEmpty {
            return "[\(timestamp)] [LoginRestoreHelper] \(normalize(message))\n"
        }
        return "[\(timestamp)] [LoginRestoreHelper] \(normalize(message)) | \(metadataText)\n"
    }

    private static func headerText() -> String {
        """
        # NRIME local developer log
        # This file stays on this Mac unless the user shares it manually.
        # Typed text is not recorded automatically.
        # Clear this file anytime from NRIME Settings > General > Developer.

        """
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
