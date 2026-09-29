import Foundation

/// Mozc, running inside the input method (built by Tools/mozc/build.sh).
///
/// It replaces mozc_server: there is no process to launch, restart or wait
/// for, and no IPC to time out — a command is a function call of about a
/// millisecond. Everything that went wrong with the server (hung or missing
/// server, stale lock files, the lost exec bit, Gatekeeper, the macOS 26.4
/// watchdog crash) belonged to that process and its IPC.
///
/// Main thread only, like everything that uses it: Mozc keeps global state
/// (profile directory, config) and is used from one thread.
final class MozcEngine {
    static let shared = MozcEngine()

    private var handle: OpaquePointer?
    private var startAttempted = false

    /// Where learning and the user dictionary live — the folder mozc_server
    /// used, so both carry over.
    static var profileDirectory: URL {
#if DEBUG
        if AppGroupDefaults.isRunningTests { return testProfileDirectory }
#endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozc")
    }

#if DEBUG
    /// Tests never read or train the owner's learning and dictionary.
    static let testProfileDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NRIME-test-mozc-\(ProcessInfo.processInfo.processIdentifier)")
    /// Test seam: only tests that set this talk to the real engine.
    static var enabledForTesting = false
    /// Test seam: what `isAvailable` answers for tests that do not use the engine.
    static var availableForTesting: Bool?
#endif

    private static var dataPath: String? {
        Bundle.main.path(forResource: "mozc", ofType: "data")
    }

    private init() {}

    /// Load the engine: 7–20 ms. Called at launch; later calls return at once.
    /// A failure (dictionary data missing) is logged once and not retried.
    @discardableResult
    func start() -> Bool {
        if handle != nil { return true }
        guard !startAttempted else { return false }
        startAttempted = true

        guard let dataPath = Self.dataPath else {
            DeveloperLogger.shared.log("Mozc", "Engine not started: mozc.data missing from the app")
            return false
        }
        let profile = Self.profileDirectory
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let startedAt = ProcessInfo.processInfo.systemUptime
        handle = nrime_mozc_new(dataPath, profile.path)
        let version = String(cString: nrime_mozc_version())
        DeveloperLogger.shared.log("Mozc", handle != nil ? "Engine started" : "Engine failed to start", metadata: [
            "ms": String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - startedAt) * 1000),
            "version": version,
        ])
        guard handle != nil else { return false }
        observeSettingsApp()
        return true
    }

    /// Whether commands can be sent (starting the engine if needed).
    var isAvailable: Bool {
#if DEBUG
        if AppGroupDefaults.isRunningTests, !Self.enabledForTesting {
            return Self.availableForTesting ?? true
        }
#endif
        return handle != nil || start()
    }

    /// One Mozc command. nil when the engine is not running.
    func eval(_ input: Mozc_Commands_Input) -> Mozc_Commands_Output? {
        guard isAvailable, let handle, let request = try? input.serializedData() else { return nil }
        var response: UnsafeMutablePointer<UInt8>?
        var responseSize = 0
        let ok = request.withUnsafeBytes { raw -> Int32 in
            nrime_mozc_eval(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count,
                            &response, &responseSize)
        }
        guard ok != 0, let response else { return nil }
        defer { nrime_mozc_free_buffer(response) }
        return try? Mozc_Commands_Output(serializedBytes: Data(bytes: response, count: responseSize))
    }

    /// Save learning to disk. Mozc also saves when a session ends; this covers
    /// quitting (updates, logout) with sessions still open.
    func sync() {
        send(.syncData)
    }

    /// Read the user dictionary again after the settings app changed it.
    /// Mozc reloads in the background; new words appear a moment later.
    func reloadUserDictionary() {
        send(.reload)
    }

    /// Forget what Mozc learned (the settings app's "clear conversion history").
    func clearLearning() {
        send(.clearUserHistory)
        send(.clearUserPrediction)
        send(.syncData)
    }

    private func send(_ type: Mozc_Commands_Input.CommandType) {
        var input = Mozc_Commands_Input()
        input.type = type
        _ = eval(input)
    }

    /// The settings app edits the dictionary file and asks for history to be
    /// cleared; the engine lives here, so it is told by notification.
    private func observeSettingsApp() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: MozcNotifications.userDictionaryChanged, object: nil, queue: .main) { _ in
            MozcEngine.shared.reloadUserDictionary()
            DeveloperLogger.shared.log("Mozc", "User dictionary reloaded")
        }
        center.addObserver(forName: MozcNotifications.clearLearning, object: nil, queue: .main) { _ in
            MozcEngine.shared.clearLearning()
            DeveloperLogger.shared.log("Mozc", "Learning cleared")
        }
    }

    deinit {
        if let handle { nrime_mozc_free(handle) }
    }
}
