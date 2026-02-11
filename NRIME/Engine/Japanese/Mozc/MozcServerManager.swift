import Foundation

/// Manages the lifecycle of the mozc_server process.
/// Launches on demand, monitors for crashes, and restarts automatically.
final class MozcServerManager {
    private var serverProcess: Process?
    private let portName = "org.mozc.inputmethod.Japanese.Converter.session"

    /// Ensures mozc_server is running. Returns true if server is available.
    func ensureServerRunning() -> Bool {
        // Check if server is already reachable via Mach port
        if isServerReachable() {
            return true
        }

        // Try to launch the server
        guard launchServer() else {
            NSLog("NRIME: Failed to launch mozc_server")
            return false
        }

        // Wait for server to register its Mach port (up to 3 seconds)
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.1)
            if isServerReachable() {
                NSLog("NRIME: mozc_server is ready")
                return true
            }
        }

        NSLog("NRIME: mozc_server launched but port not available")
        return false
    }

    /// Kill any existing mozc_server (including stale ones from previous NRIME instances),
    /// then relaunch. Returns true if the fresh server is available.
    func restartServer() -> Bool {
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["mozc_server"]
        killTask.standardOutput = FileHandle.nullDevice
        killTask.standardError = FileHandle.nullDevice
        try? killTask.run()
        killTask.waitUntilExit()

        serverProcess?.terminate()
        serverProcess = nil

        // Brief wait for Mach port to be deregistered
        Thread.sleep(forTimeInterval: 0.2)

        return ensureServerRunning()
    }

    /// Shuts down the managed mozc_server process.
    func shutdownServer() {
        guard let process = serverProcess, process.isRunning else { return }
        process.terminate()
        serverProcess = nil
        NSLog("NRIME: mozc_server terminated")
    }

    // MARK: - Private

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
            self?.serverProcess = nil
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
