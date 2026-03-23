import Foundation

/// Manages the lifecycle of the mozc_server process.
/// Launches on demand, monitors for crashes, and restarts automatically.
final class MozcServerManager {
    static let shared = MozcServerManager()

    private let launchAgentLabel = "com.nrime.inputmethod.mozcserver"
    private var serverProcess: Process?
    private let serverProcessLock = NSLock()
    private let launchQueue = DispatchQueue(label: "com.nrime.mozc.launch")
    private let launchQueueKey = DispatchSpecificKey<Void>()
    private let portName = "org.mozc.inputmethod.Japanese.Converter.session"
    private let warmupQueue = DispatchQueue(label: "com.nrime.mozc.warmup", qos: .utility)
    private let launchPollInterval: TimeInterval = 0.05
    private let restartWaitBudget: TimeInterval = 3.0
    private let launchWaitBudget: TimeInterval = 3.0
    private let prewarmWaitBudget: TimeInterval = 3.0

    private enum ServerPreparationResult {
        case reachable
        case alreadyRunning
        case launched
        case launchFailed
    }

    private init() {
        launchQueue.setSpecific(key: launchQueueKey, value: ())
    }

    private func debugLog(_ msg: String) {
        let line = "ServerManager: \(msg)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/nrime-debug.log") {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            FileManager.default.createFile(atPath: "/tmp/nrime-debug.log", contents: line.data(using: .utf8))
        }
    }

    /// Launch Mozc in the background so the first conversion does not pay startup cost.
    func prewarmServer() {
        warmupQueue.async { [weak self] in
            guard let self else { return }
            switch self.prepareServerForUse() {
            case .reachable:
                return
            case .alreadyRunning, .launched:
                _ = self.waitUntilReachable(timeout: self.prewarmWaitBudget)
            case .launchFailed:
                return
            }
        }
    }

    /// Ensures mozc_server is running. Returns true if server is available.
    func ensureServerRunning() -> Bool {
        switch prepareServerForUse() {
        case .reachable:
            return true
        case .alreadyRunning:
            return waitUntilReachable(timeout: launchWaitBudget)
        case .launched:
            return waitUntilReachable(timeout: launchWaitBudget)
        case .launchFailed:
            NSLog("NRIME: Failed to launch mozc_server")
            return false
        }
    }

    /// Kill any existing mozc_server (including stale ones from previous NRIME instances),
    /// then relaunch. Returns true if the fresh server is available.
    func restartServer() -> Bool {
        let launched = withLaunchQueue { () -> Bool in
            killStaleServers()
            return launchServerViaLaunchAgent() || launchServer()
        }
        guard launched else {
            return false
        }
        return waitUntilReachable(timeout: restartWaitBudget)
    }

    /// Shuts down the managed mozc_server process.
    func shutdownServer() {
        _ = stopLaunchAgentServer()
        serverProcessLock.lock()
        guard let process = serverProcess, process.isRunning else {
            serverProcessLock.unlock()
            return
        }
        process.terminate()
        serverProcess = nil
        serverProcessLock.unlock()
        NSLog("NRIME: mozc_server terminated")
    }

    // MARK: - Private

    private func prepareServerForUse() -> ServerPreparationResult {
        withLaunchQueue {
            if isServerReachable() {
                debugLog("already reachable")
                return .reachable
            }

            let isRunning = serverProcessLock.withLock { serverProcess?.isRunning } ?? false
            if isRunning {
                debugLog("process running but not reachable")
                return .alreadyRunning
            }

            debugLog("not found, launching...")
            killStaleServers()
            let launched = launchServerViaLaunchAgent() || launchServer()
            debugLog("launchServer result=\(launched)")
            return launched ? .launched : .launchFailed
        }
    }

    private func withLaunchQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: launchQueueKey) != nil {
            return work()
        }
        return launchQueue.sync(execute: work)
    }

    /// Kill any existing mozc_server processes that are not managed by this instance.
    /// This handles stale servers left behind after NRIME is reinstalled/restarted.
    private func killStaleServers() {
        _ = stopLaunchAgentServer()

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["mozc_server"]
        killTask.standardOutput = FileHandle.nullDevice
        killTask.standardError = FileHandle.nullDevice
        try? killTask.run()
        killTask.waitUntilExit()

        serverProcessLock.withLock {
            serverProcess?.terminate()
            serverProcess = nil
        }

        // Remove stale lock files left by crashed mozc_server.
        MozcClient.removeStaleLockFiles()

        // Wait for Mach port teardown. Kernel may hold stale port briefly after process dies.
        Thread.sleep(forTimeInterval: 0.5)
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

        // Redirect stderr to debug log for crash diagnosis
        process.standardOutput = FileHandle.nullDevice
        let logPath = "/tmp/nrime-mozc-server.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            logHandle.seekToEndOfFile()
            process.standardError = logHandle
        } else {
            process.standardError = FileHandle.nullDevice
        }

        process.terminationHandler = { [weak self] proc in
            NSLog("NRIME: mozc_server terminated with status \(proc.terminationStatus)")
            self?.serverProcessLock.withLock {
                self?.serverProcess = nil
            }
        }

        do {
            try process.run()
            serverProcessLock.withLock { serverProcess = process }
            NSLog("NRIME: mozc_server launched (PID: \(process.processIdentifier))")
            return true
        } catch {
            NSLog("NRIME: Failed to launch mozc_server: \(error)")
            return false
        }
    }

    private func launchServerViaLaunchAgent() -> Bool {
        guard let plistPath = installedLaunchAgentPlistPath() else {
            debugLog("launch agent plist not found; falling back to direct launch")
            return false
        }

        let domain = "gui/\(getuid())"
        _ = runLaunchCtl(arguments: ["bootout", domain, plistPath])
        let bootstrapStatus = runLaunchCtl(arguments: ["bootstrap", domain, plistPath])
        debugLog("launchctl bootstrap status=\(bootstrapStatus) plist=\(plistPath)")

        let kickstartStatus = runLaunchCtl(arguments: ["kickstart", "-k", "\(domain)/\(launchAgentLabel)"])
        debugLog("launchctl kickstart status=\(kickstartStatus)")
        return kickstartStatus == 0 || bootstrapStatus == 0
    }

    @discardableResult
    private func stopLaunchAgentServer() -> Bool {
        let domain = "gui/\(getuid())"
        let killStatus = runLaunchCtl(arguments: ["kill", "TERM", "\(domain)/\(launchAgentLabel)"])
        debugLog("launchctl kill status=\(killStatus)")
        return killStatus == 0
    }

    private func installedLaunchAgentPlistPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Library/LaunchAgents/\(launchAgentLabel).plist",
            "/Library/LaunchAgents/\(launchAgentLabel).plist"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    @discardableResult
    private func runLaunchCtl(arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            debugLog("launchctl failed args=\(arguments.joined(separator: " ")) error=\(error)")
            return -1
        }
    }

    private func serverBinaryPath() -> String? {
        debugLog("Bundle.main.bundlePath=\(Bundle.main.bundlePath)")
        // Look in the app bundle's Resources
        if let path = Bundle.main.path(forResource: "mozc_server", ofType: nil) {
            debugLog("mozc_server found in bundle: \(path)")
            return path
        }
        // Fallback: look next to the app bundle (for development)
        let appDir = Bundle.main.bundlePath
        let siblingPath = (appDir as NSString).deletingLastPathComponent + "/mozc_server"
        if FileManager.default.isExecutableFile(atPath: siblingPath) {
            debugLog("mozc_server found as sibling: \(siblingPath)")
            return siblingPath
        }
        debugLog("mozc_server NOT FOUND anywhere")
        return nil
    }

    deinit {
        shutdownServer()
    }
}
