import AppKit
import Foundation

/// Mozc, running inside the input method.
///
/// The engine is libnrime_mozc.dylib (Tools/mozc) with its mozc.data, loaded
/// at run time: the newest good one downloaded by MozcUpdater, else the one
/// bundled in the app. A newer Mozc therefore needs no new NRIME.
///
/// It replaced mozc_server: there is no process to launch, restart or wait
/// for, and no IPC to time out — a command is a function call of about a
/// millisecond. Everything that went wrong with the server (hung or missing
/// server, stale lock files, the lost exec bit, Gatekeeper, the macOS 26.4
/// watchdog crash) belonged to that process and its IPC.
///
/// Main thread only, like everything that uses it: Mozc keeps global state
/// (profile directory, config) and is used from one thread.
final class MozcEngine {
    static let shared = MozcEngine()

    /// The C API (nrime_mozc.h), resolved from the loaded library.
    private struct API {
        typealias ABIVersion = @convention(c) () -> Int32
        typealias New = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> OpaquePointer?
        typealias Free = @convention(c) (OpaquePointer?) -> Void
        typealias Eval = @convention(c) (OpaquePointer?, UnsafePointer<UInt8>?, Int,
                                         UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
                                         UnsafeMutablePointer<Int>?) -> Int32
        typealias FreeBuffer = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void
        typealias Version = @convention(c) () -> UnsafePointer<CChar>?

        let abiVersion: ABIVersion
        let new: New
        let free: Free
        let eval: Eval
        let freeBuffer: FreeBuffer
        let version: Version

        init?(library: UnsafeMutableRawPointer) {
            func symbol<T>(_ name: String, _ type: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: type) }
            }
            guard let abiVersion = symbol("nrime_mozc_abi_version", ABIVersion.self),
                  let new = symbol("nrime_mozc_new", New.self),
                  let free = symbol("nrime_mozc_free", Free.self),
                  let eval = symbol("nrime_mozc_eval", Eval.self),
                  let freeBuffer = symbol("nrime_mozc_free_buffer", FreeBuffer.self),
                  let version = symbol("nrime_mozc_version", Version.self) else { return nil }
            self.abiVersion = abiVersion
            self.new = new
            self.free = free
            self.eval = eval
            self.freeBuffer = freeBuffer
            self.version = version
        }
    }

    private var api: API?
    private var handle: OpaquePointer?
    private var startAttempted = false
    /// The engine in use.
    private(set) var active: MozcComponent?

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

    private init() {}

#if DEBUG
    /// Test seam: a separate engine, to exercise loading and fallback.
    static func makeForTesting() -> MozcEngine { MozcEngine() }
#endif

    /// Load the engine: the best candidate that loads and answers
    /// (MozcComponents.candidates). Called at launch; later calls return at
    /// once. Nothing loading at all is logged once and not retried.
    @discardableResult
    func start() -> Bool {
        if handle != nil { return true }
        guard !startAttempted else { return false }
        startAttempted = true

        let profile = Self.profileDirectory
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        for component in MozcComponents.candidates() where load(component, profile: profile) {
            MozcComponents.prune(keeping: component)
            Self.updateStatus { status in
                status.active = component.info
                status.activeSource = component.source.rawValue
                if let pending = status.pending, pending.commit == component.commit || pending.date <= component.date {
                    status.pending = nil
                }
            }
            observeSettingsApp()
            return true
        }
        DeveloperLogger.shared.log("Mozc", "Engine not started: nothing could be loaded")
        return false
    }

    /// Load one component and check that it answers. A downloaded one that
    /// fails is marked bad (MozcComponents), and the next candidate is tried.
    private func load(_ component: MozcComponent, profile: URL) -> Bool {
        guard MozcComponents.beginLoad(component) else { return false }
        let startedAt = ProcessInfo.processInfo.systemUptime
        func failed(_ reason: String) -> Bool {
            if component.source == .downloaded {
                MozcComponents.markBad(component, reason: reason)
            } else {
                DeveloperLogger.shared.log("Mozc", "Bundled engine failed", metadata: ["reason": reason])
            }
            return false
        }

        // A library that failed stays loaded: unloading C++ code is not safe,
        // and it is simply never called.
        guard let library = dlopen(component.libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return failed("dlopen: " + (dlerror().map { String(cString: $0) } ?? "?"))
        }
        guard let api = API(library: library) else { return failed("C API missing") }
        let abi = api.abiVersion()
        guard abi == Int32(MozcComponents.supportedABI) else { return failed("C API version \(abi)") }
        guard let handle = api.new(component.dataURL.path, profile.path) else {
            return failed("engine did not start")
        }
        self.api = api
        self.handle = handle
        guard answers() else {
            api.free(handle)
            self.api = nil
            self.handle = nil
            return failed("engine did not answer")
        }
        MozcComponents.endLoad(component)
        active = component

        DeveloperLogger.shared.log("Mozc", "Engine started", metadata: [
            "ms": String(format: "%.0f", (ProcessInfo.processInfo.systemUptime - startedAt) * 1000),
            "version": api.version().map { String(cString: $0) } ?? component.version,
            "date": component.date,
            "commit": String(component.commit.prefix(7)),
            "source": component.source.rawValue,
        ])
        return true
    }

    /// A session opens and closes.
    private func answers() -> Bool {
        var create = Mozc_Commands_Input()
        create.type = .createSession
        guard let output = evaluate(create), output.hasID, output.id != 0 else { return false }
        var delete = Mozc_Commands_Input()
        delete.type = .deleteSession
        delete.id = output.id
        _ = evaluate(delete)
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
        guard isAvailable else { return nil }
        return evaluate(input)
    }

    private func evaluate(_ input: Mozc_Commands_Input) -> Mozc_Commands_Output? {
        guard let api, let handle, let request = try? input.serializedData() else { return nil }
        var response: UnsafeMutablePointer<UInt8>?
        var responseSize = 0
        let ok = request.withUnsafeBytes { raw -> Int32 in
            api.eval(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &response, &responseSize)
        }
        guard ok != 0, let response else { return nil }
        defer { api.freeBuffer(response) }
        return try? Mozc_Commands_Output(serializedBytes: Data(bytes: response, count: responseSize))
    }

    /// Save learning to disk. Mozc also saves when a session ends.
    func sync() {
        syncScheduled = false
#if DEBUG
        syncCountForTesting += 1
#endif
        send(.syncData)
    }

    /// Mozc keeps what it learns in memory until a sync. mozc_server had a
    /// watchdog sending CLEANUP — which syncs — every few minutes; in process
    /// nothing does, and an update ends the input method with killall, which
    /// skips applicationWillTerminate. So a commit schedules a save shortly
    /// after: one for any number of commits in that window.
    func learningChanged() {
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncDelay) {
            if MozcEngine.shared.syncScheduled {
                MozcEngine.shared.sync()
            }
        }
    }

    private var syncScheduled = false
    static var syncDelay: TimeInterval = 20

#if DEBUG
    /// Test seam: how many times learning was saved.
    private(set) var syncCountForTesting = 0
#endif

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

    // MARK: - Status and the settings app

    /// Change the MozcStatus the settings app shows, and tell it.
    static func updateStatus(_ change: (inout MozcStatus) -> Void) {
        let defaults = AppGroupDefaults.make()
        var status = MozcStatus.load(from: defaults) ?? MozcStatus()
        change(&status)
        status.save(to: defaults)
        DistributedNotificationCenter.default().postNotificationName(
            MozcNotifications.statusChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// The settings app edits the dictionary file, clears history and asks
    /// about updates; the engine lives here, so it is told by notification.
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
        center.addObserver(forName: MozcNotifications.applyUpdate, object: nil, queue: .main) { _ in
            // Quit; macOS starts the input method again at the next key
            // press, and that start loads the newer engine.
            DeveloperLogger.shared.log("Mozc", "Quitting to switch engines")
            NSApp.terminate(nil)
        }
    }
}
