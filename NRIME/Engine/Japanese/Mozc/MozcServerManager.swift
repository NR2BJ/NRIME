import Foundation

/// Manages the lifecycle of the mozc_server process.
/// Launches on demand, monitors for crashes, and restarts automatically.
final class MozcServerManager {
    static let shared = MozcServerManager()

    private var serverProcess: Process?
    private let portName = "org.mozc.inputmethod.Japanese.Converter.session"
    private let warmupQueue = DispatchQueue(label: "com.nrime.mozc.warmup", qos: .utility)
    private let launchPollInterval: TimeInterval = 0.02
    private let restartWaitBudget: TimeInterval = 0.12
    private let prewarmWaitBudget: TimeInterval = 1.0

    private init() {}

    /// Launch Mozc in the background so the first conversion does not pay startup cost.
    func prewarmServer() {
        warmupQueue.async { [weak self] in
            guard let self else { return }
            if self.isServerReachable() {
                return
            }
            if self.serverProcess?.isRunning != true {
                self.killStaleServers()
                guard self.launchServer() else { return }
            }
            _ = self.waitUntilReachable(timeout: self.prewarmWaitBudget)
        }
    }

    /// Ensures mozc_server is running. Returns true if server is available.
    func ensureServerRunning() -> Bool {
        // Check if server is already reachable via Mach port
        if isServerReachable() {
            return true
        }

        // If we already launched the process, let the current key event fail fast
        // instead of waiting in the app's input path.
        if serverProcess?.isRunning == true {
            return false
        }

        // Kill any stale mozc_server from a previous NRIME instance whose
        // Mach port is no longer reachable but still occupies the port name.
        killStaleServers()

        // Try to launch the server
        guard launchServer() else {
            NSLog("NRIME: Failed to launch mozc_server")
            return false
        }

        return waitUntilReachable(timeout: launchPollInterval * 2)
    }

    /// Kill any existing mozc_server (including stale ones from previous NRIME instances),
    /// then relaunch. Returns true if the fresh server is available.
    func restartServer() -> Bool {
        killStaleServers()
        guard launchServer() else {
            return false
        }
        return waitUntilReachable(timeout: restartWaitBudget)
    }

    /// Shuts down the managed mozc_server process.
    func shutdownServer() {
        guard let process = serverProcess, process.isRunning else { return }
        process.terminate()
        serverProcess = nil
        NSLog("NRIME: mozc_server terminated")
    }

    // MARK: - Private

    /// Kill any existing mozc_server processes that are not managed by this instance.
    /// This handles stale servers left behind after NRIME is reinstalled/restarted.
    private func killStaleServers() {
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["mozc_server"]
        killTask.standardOutput = FileHandle.nullDevice
        killTask.standardError = FileHandle.nullDevice
        try? killTask.run()
        killTask.waitUntilExit()

        serverProcess?.terminate()
        serverProcess = nil

        // Brief wait for Mach port teardown. This runs only on explicit restart/prewarm paths.
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func waitUntilReachable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isServerReachable() {
                NSLog("NRIME: mozc_server is ready")
                return true
            }
            Thread.sleep(forTimeInterval: launchPollInterval)
        } while Date() < deadline

        return isServerReachable()
    }

    private func isServerReachable() -> Bool {
        var serverPort: mach_port_t = 0
        let kr = bootstrap_look_up(bootstrap_port, portName, &serverPort)
        if kr == KERN_SUCCESS && serverPort != 0 {
            mach_port_deallocate(mach_task_self_, serverPort)
            return true
        }
        return false
    }

    private func launchServer() -> Bool {
        guard let binaryPath = serverBinaryPath() else {
            NSLog("NRIME: mozc_server binary not found in bundle")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        // --nodetach keeps server in foreground so we can manage it
        process.arguments = ["--nodetach"]

        // Suppress stdout/stderr
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] proc in
            NSLog("NRIME: mozc_server terminated with status \(proc.terminationStatus)")
            DispatchQueue.main.async {
                self?.serverProcess = nil
            }
        }

        do {
            try process.run()
            serverProcess = process
            NSLog("NRIME: mozc_server launched (PID: \(process.processIdentifier))")
            return true
        } catch {
            NSLog("NRIME: Failed to launch mozc_server: \(error)")
            return false
        }
    }

    private func serverBinaryPath() -> String? {
        // Look in the app bundle's Resources
        if let path = Bundle.main.path(forResource: "mozc_server", ofType: nil) {
            return path
        }
        // Fallback: look next to the app bundle (for development)
        let appDir = Bundle.main.bundlePath
        let siblingPath = (appDir as NSString).deletingLastPathComponent + "/mozc_server"
        if FileManager.default.isExecutableFile(atPath: siblingPath) {
            return siblingPath
        }
        return nil
    }

    deinit {
        shutdownServer()
    }
}
