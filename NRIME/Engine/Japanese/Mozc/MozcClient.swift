import Foundation
import SwiftProtobuf

/// One Mozc session: builds the protocol messages and sends them to the engine
/// running in this process (MozcEngine). Each input controller has its own.
///
/// Main thread only, like the engine.
final class MozcClient {
    private var sessionId: UInt64 = 0
    private var hasSession = false
    /// After a failed session creation, the next keys do not each try again.
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

    /// Create a new session.
    func createSession() -> Bool {
        var input = Mozc_Commands_Input()
        input.type = .createSession

        guard let output = call(input), output.hasID else {
            DeveloperLogger.shared.log("Mozc", "Session creation failed")
            return false
        }
        sessionId = output.id
        hasSession = true
        DeveloperLogger.shared.log("Mozc", "Session created", metadata: ["sessionId": "\(output.id)"])

        // Configure the session with our Request flags.
        var setRequest = Mozc_Commands_Input()
        setRequest.type = .setRequest
        setRequest.id = sessionId
        setRequest.request = mozcRequest
        _ = call(setRequest)
        return true
    }

    /// Send a key event to the current session.
    func sendKey(_ keyEvent: Mozc_Commands_KeyEvent) -> Mozc_Commands_Output? {
        guard ensureSession() else { return nil }

        var input = Mozc_Commands_Input()
        input.type = .sendKey
        input.id = sessionId
        input.key = keyEvent
        initInput(&input)
        return call(input)
    }

    /// Send a session command (SUBMIT, REVERT, SELECT_CANDIDATE, etc.)
    func sendCommand(_ command: Mozc_Commands_SessionCommand,
                     context: Mozc_Commands_Context? = nil) -> Mozc_Commands_Output? {
        guard ensureSession() else { return nil }

        var input = Mozc_Commands_Input()
        input.type = .sendCommand
        input.id = sessionId
        input.command = command
        initInput(&input)
        if let context {
            input.context = context
        }
        return call(input)
    }

    /// End the session. Mozc saves what it learned when a session ends.
    func deleteSession() {
        guard hasSession else { return }
        var input = Mozc_Commands_Input()
        input.type = .deleteSession
        input.id = sessionId
        _ = call(input)
        forgetSession()
    }

    /// Drop the session here without telling Mozc — it did not answer, so it
    /// would not answer a delete either. The next command starts a new one.
    func forgetSession() {
        hasSession = false
        sessionId = 0
    }

    /// Replace the session after an error (a stale session ID).
    func resetSession() {
        deleteSession()
    }

    // MARK: - Private

    /// Attach config and request to every Input message.
    private func initInput(_ input: inout Mozc_Commands_Input) {
        input.config = mozcConfig
        input.request = mozcRequest
    }

    private func ensureSession() -> Bool {
        if hasSession { return true }
        guard Date() >= sessionRetryNotBefore else { return false }
        if createSession() {
            sessionRetryNotBefore = .distantPast
            return true
        }
        // The engine is not running (its data could not be loaded): Japanese
        // conversion is unavailable, and asking on every key only fills the log.
        sessionRetryNotBefore = Date().addingTimeInterval(sessionFailureCooldown)
        return false
    }

#if DEBUG
    /// Test seam: answers requests in place of the engine (none, by default).
    static var responderForTesting: ((Mozc_Commands_Input) -> Mozc_Commands_Output?)?
#endif

    private func call(_ input: Mozc_Commands_Input) -> Mozc_Commands_Output? {
#if DEBUG
        // Tests use a responder, or the real engine with a throwaway profile
        // only when a test asks for it (MozcEngine.enabledForTesting).
        if AppGroupDefaults.isRunningTests {
            if let responder = Self.responderForTesting { return responder(input) }
            guard MozcEngine.enabledForTesting else { return nil }
        }
#endif
        let start = ProcessInfo.processInfo.systemUptime
        let output = MozcEngine.shared.eval(input)
        let duration = ProcessInfo.processInfo.systemUptime - start
        // A committed result is something Mozc learns from: have it saved.
        if let output, output.hasResult {
            MozcEngine.shared.learningChanged()
        }
        // A command takes about a millisecond in process; log the exceptions
        // (by type, never content) so slow keys can be traced to Mozc or not.
        if duration >= 0.02 {
            DeveloperLogger.shared.log("Mozc", "Slow call", metadata: [
                "type": "\(input.type)",
                "ms": String(format: "%.0f", duration * 1000),
                "ok": output != nil ? "Y" : "N",
            ])
        }
        return output
    }
}
