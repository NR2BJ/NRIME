import Foundation
import SwiftProtobuf

/// Low-level Mozc IPC client using Mach ports.
/// Communicates with mozc_server via OOL Mach messages containing serialized protobuf.
final class MozcClient {
    private let portName = "org.mozc.inputmethod.Japanese.Converter.session"
    private let protocolVersion: mach_msg_id_t = 3  // IPC_PROTOCOL_VERSION
    private let rpcTimeout: mach_msg_timeout_t = 750
    /// Session setup waits longer than a keystroke, but still on the keystroke
    /// thread — 5 s used to be the cap. A server that takes longer is treated
    /// as hung and restarted in the background.
    private let sessionTimeout: mach_msg_timeout_t = 2_000

    private var sessionId: UInt64 = 0
    private var hasSession = false
    private let sessionQueue = DispatchQueue(label: "com.nrime.mozc.session")
    private let sessionCreationLock = NSLock()
    private var sessionRetryNotBefore = Date.distantPast
    private let sessionFailureCooldown: TimeInterval = 2.0

    /// Mozc config attached to every Input message.
    ///
    /// Suggestions while typing are off: NRIME only converts on Space (no
    /// prediction, no live conversion), and feeding a reading one character at
    /// a time otherwise makes Mozc compute a suggestion list for every one.
    private let mozcConfig: Mozc_Config_Config = {
        var config = Mozc_Config_Config()
        config.useRealtimeConversion = false
        config.useHistorySuggest = false
        config.useDictionarySuggest = false
        return config
    }()

    /// Mozc request flags. No zero-query (next-word) suggestions — prediction is gone.
    private let mozcRequest: Mozc_Commands_Request = {
        var request = Mozc_Commands_Request()
        request.zeroQuerySuggestion = false
        return request
    }()

    // MARK: - Public API

    /// Create a new session with mozc_server.
    func createSession() -> Bool {
        var input = Mozc_Commands_Input()
        input.type = .createSession

        guard let output = call(input, timeout: sessionTimeout) else {
            DeveloperLogger.shared.log("Mozc", "Session creation failed — IPC call returned nil")
            return false
        }

        if output.hasID {
            sessionQueue.sync {
                sessionId = output.id
                hasSession = true
            }
            DeveloperLogger.shared.log("Mozc", "Session created", metadata: ["sessionId": "\(output.id)"])

            // Send SET_REQUEST to configure the session with our Request flags
            var setReqInput = Mozc_Commands_Input()
            setReqInput.type = .setRequest
            setReqInput.id = sessionQueue.sync { sessionId }
            setReqInput.request = mozcRequest
            _ = call(setReqInput, timeout: sessionTimeout)

            return true
        }
        DeveloperLogger.shared.log("Mozc", "Session creation failed — no ID in response")
        return false
    }

    /// Send a key event to the current session.
    func sendKey(_ keyEvent: Mozc_Commands_KeyEvent) -> Mozc_Commands_Output? {
        guard ensureSession() else {
            return nil
        }

        var input = Mozc_Commands_Input()
        input.type = .sendKey
        input.id = sessionQueue.sync { sessionId }
        input.key = keyEvent
        initInput(&input)

        return call(input, timeout: rpcTimeout)
    }

    /// Send a session command (SUBMIT, REVERT, SELECT_CANDIDATE, etc.)
    func sendCommand(_ command: Mozc_Commands_SessionCommand,
                     context: Mozc_Commands_Context? = nil) -> Mozc_Commands_Output? {
        guard ensureSession() else { return nil }

        var input = Mozc_Commands_Input()
        input.type = .sendCommand
        input.id = sessionQueue.sync { sessionId }
        input.command = command
        initInput(&input)
        if let context = context {
            input.context = context
        }

        return call(input, timeout: rpcTimeout)
    }

    /// Delete the current session.
    func deleteSession() {
        let currentId: UInt64? = sessionQueue.sync {
            guard hasSession else { return nil }
            return sessionId
        }
        guard let id = currentId else { return }

        var input = Mozc_Commands_Input()
        input.type = .deleteSession
        input.id = id

        _ = call(input, timeout: rpcTimeout)
        sessionQueue.sync {
            hasSession = false
            sessionId = 0
        }
    }

    /// Drop the session locally without contacting the server — for when it
    /// did not answer, and asking it to delete the session would only wait again.
    func forgetSession() {
        sessionQueue.sync {
            hasSession = false
            sessionId = 0
        }
    }

    /// Whether a session exists — sending to one that does not creates it first.
    var hasActiveSession: Bool {
        sessionQueue.sync { hasSession }
    }

    /// Reset session state (e.g., after error).
    /// Best-effort: attempts to delete the server-side session before clearing local state.
    func resetSession() {
        let currentId: UInt64? = sessionQueue.sync {
            guard hasSession else { return nil }
            return sessionId
        }
        if let id = currentId {
            var input = Mozc_Commands_Input()
            input.type = .deleteSession
            input.id = id
            _ = call(input, timeout: rpcTimeout)  // best-effort; ignore failure
        }
        sessionQueue.sync {
            hasSession = false
            sessionId = 0
        }
    }

    // MARK: - Private

    /// Attach config and request to every Input message.
    private func initInput(_ input: inout Mozc_Commands_Input) {
        input.config = mozcConfig
        input.request = mozcRequest
    }

    private func ensureSession() -> Bool {
        if sessionQueue.sync(execute: { hasSession }) { return true }
        sessionCreationLock.lock()
        defer { sessionCreationLock.unlock() }

        let now = Date()
        if now < sessionRetryNotBefore {
            DeveloperLogger.shared.log("Mozc", "Session retry in backoff period")
            return false
        }

        if sessionQueue.sync(execute: { hasSession }) { return true }
        if createSession() {
            sessionRetryNotBefore = .distantPast
            return true
        }

        // No session: the server crashed, hung or left a stale lock. Restart
        // it in the background — this keystroke does not wait for that — and
        // back off briefly so the following keys do not each try again.
        DeveloperLogger.shared.log("Mozc", "Session creation failed — restarting server in the background",
                                   metadata: ["cooldown": "\(sessionFailureCooldown)s"])
        MozcServerManager.shared.restartInBackground()
        sessionRetryNotBefore = Date().addingTimeInterval(sessionFailureCooldown)
        return false
    }

    /// Remove mozc_server lock files that prevent new instances from starting.
    static func removeStaleLockFiles() {
        let mozcDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozc")
        let fm = FileManager.default
        for name in [".server.lock", ".session.ipc"] {
            let path = mozcDir.appendingPathComponent(name).path
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            try? fm.removeItem(atPath: path)
        }
    }

#if DEBUG
    /// Test seam: answers requests in place of the server (none, by default).
    static var responderForTesting: ((Mozc_Commands_Input) -> Mozc_Commands_Output?)?
#endif

    /// Serialize Input protobuf, send via Mach port, receive and deserialize Output.
    /// Mozc server expects serialized Input (not Command) and returns serialized Output.
    private func call(_ input: Mozc_Commands_Input,
                      timeout overrideTimeout: mach_msg_timeout_t? = nil) -> Mozc_Commands_Output? {
#if DEBUG
        // Tests never talk to the Mozc server that is running for the user —
        // it shares the port name, and conversions would train its history.
        if AppGroupDefaults.isRunningTests { return Self.responderForTesting?(input) }
#endif
        // Serialize Input directly — Mozc server parses request as Input
        let requestData: Data
        do {
            requestData = try input.serializedData()
        } catch {
            return nil
        }

        let resolvedTimeout = overrideTimeout ?? timeout(for: input.type)

        // Send via Mach IPC. The call is synchronous and usually on the main
        // thread, where every key waits behind it: log the slow ones by type
        // (never content) so lag reports can be traced to Mozc or cleared of it.
        let callStart = ProcessInfo.processInfo.systemUptime
        let response = machCall(request: requestData, timeout: resolvedTimeout)
        let callDuration = ProcessInfo.processInfo.systemUptime - callStart
        if callDuration >= 0.05 {
            DeveloperLogger.shared.log("Mozc", "Slow IPC", metadata: [
                "type": "\(input.type)",
                "ms": String(format: "%.0f", callDuration * 1000),
                "ok": response != nil ? "Y" : "N",
                "mainThread": Thread.isMainThread ? "Y" : "N",
            ])
        }
        guard let responseData = response else {
            return nil
        }

        // Deserialize response as Output directly — Mozc server serializes Output
        do {
            return try Mozc_Commands_Output(serializedBytes: responseData)
        } catch {
            return nil
        }
    }

    // MARK: - Mach IPC (C shim)

    /// Send/receive via C implementation that matches upstream mozc mach_ipc.cc exactly.
    /// This eliminates all Swift-to-Mach IPC subtle differences that caused empty responses.
    private func machCall(request: Data, timeout: mach_msg_timeout_t) -> Data? {
        return request.withUnsafeBytes { rawBuffer -> Data? in
            guard let requestPtr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            var responsePtr: UnsafeMutablePointer<UInt8>? = nil
            var responseSize: Int = 0

            let ok = nrime_mozc_call(
                portName,
                requestPtr,
                request.count,
                &responsePtr,
                &responseSize,
                timeout
            )

            guard ok, let ptr = responsePtr, responseSize > 0 else {
                DeveloperLogger.shared.log("Mozc", "Mach IPC failed",
                                           metadata: ["requestSize": "\(request.count)"])
                return nil
            }

            let data = Data(bytes: ptr, count: responseSize)
            free(ptr)
            return data
        }
    }

    private func timeout(for inputType: Mozc_Commands_Input.CommandType) -> mach_msg_timeout_t {
        switch inputType {
        case .createSession, .setRequest, .reload, .reloadAndWait:
            return sessionTimeout
        default:
            return rpcTimeout
        }
    }
}
