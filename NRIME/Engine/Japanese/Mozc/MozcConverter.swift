import Foundation
import InputMethodKit

/// Result of processing a Mozc Output.
struct MozcResult {
    var committedText: String? = nil
    var preedit: Mozc_Commands_Preedit? = nil
    var hasCandidates: Bool = false
    var consumed: Bool = true
}

/// Manages Mozc conversion state and candidate display.
final class MozcConverter {
    private let client = MozcClient()
    private let serverManager = MozcServerManager()

    /// Current candidate strings for CandidatePanel display.
    var currentCandidateStrings: [String] = []

    /// The original hiragana text being converted.
    var originalHiragana: String = ""

    /// Whether Mozc server is available.
    private(set) var isAvailable = false

    /// Whether Mozc currently has an active conversion (segments in preedit).
    private(set) var isConverting: Bool = false

    // MARK: - Key Forwarding API

    /// Forward a key event to the active Mozc session.
    func sendKeyEvent(_ keyEvent: Mozc_Commands_KeyEvent) -> Mozc_Commands_Output? {
        return client.sendKey(keyEvent)
    }

    /// Send a session command to Mozc.
    func sendCommand(_ command: Mozc_Commands_SessionCommand) -> Mozc_Commands_Output? {
        return client.sendCommand(command)
    }

    /// Feed hiragana characters to Mozc to build composition state (without triggering conversion).
    /// If IPC fails (stale server), automatically restarts mozc_server and retries once.
    func feedHiragana(_ hiragana: String) -> Bool {
        guard serverManager.ensureServerRunning() else {
            isAvailable = false
            return false
        }
        isAvailable = true

        let chars = Array(hiragana)
        var retried = false
        var i = 0

        while i < chars.count {
            var keyEvent = Mozc_Commands_KeyEvent()
            keyEvent.keyString = String(chars[i])

            if let output = client.sendKey(keyEvent) {
                if output.hasErrorCode {
                    client.resetSession()
                    return false
                }
                i += 1
            } else if !retried {
                // IPC failure — restart server and retry from beginning
                client.resetSession()
                guard serverManager.restartServer() else {
                    isAvailable = false
                    return false
                }
                retried = true
                i = 0
            } else {
                client.resetSession()
                return false
            }
        }
        return true
    }

    /// Process a Mozc Output, updating internal state.
    func updateFromOutput(_ output: Mozc_Commands_Output) -> MozcResult {
        var result = MozcResult()

        // 1. Check for committed result
        if output.hasResult, output.result.hasValue {
            result.committedText = output.result.value
        }

        // 2. Check for preedit (segments)
        if output.hasPreedit, !output.preedit.segment.isEmpty {
            result.preedit = output.preedit
            isConverting = true
        } else {
            isConverting = false
        }

        // 3. Extract candidates
        extractCandidates(from: output)
        result.hasCandidates = !currentCandidateStrings.isEmpty

        result.consumed = output.consumed
        return result
    }

    /// Submit the current conversion and return the committed text.
    func submit() -> String? {
        var submitCmd = Mozc_Commands_SessionCommand()
        submitCmd.type = .submit

        guard let output = client.sendCommand(submitCmd) else { return nil }

        isConverting = false
        currentCandidateStrings = []

        if output.hasResult, output.result.hasValue {
            return output.result.value
        }

        // Fallback: preedit text
        if output.hasPreedit {
            let text = output.preedit.segment.map { $0.value }.joined()
            if !text.isEmpty { return text }
        }

        return nil
    }

    // MARK: - Conversion

    /// Convert hiragana to kanji candidates via Mozc.
    /// Returns true if conversion produced a preedit or candidates.
    /// If IPC fails after feedHiragana, restarts server and retries the full sequence once.
    func convert(hiragana: String) -> Bool {
        currentCandidateStrings = []
        originalHiragana = hiragana

        guard feedHiragana(hiragana) else { return false }

        // Send Space to trigger conversion
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space

        var output = client.sendKey(spaceKey)
        if output == nil {
            // Space key IPC failed — restart server and retry entire sequence
            client.resetSession()
            guard serverManager.restartServer(),
                  feedHiragana(hiragana) else {
                return false
            }
            output = client.sendKey(spaceKey)
            guard output != nil else {
                client.resetSession()
                return false
            }
        }

        isConverting = true
        extractCandidates(from: output!)

        return !currentCandidateStrings.isEmpty || output!.hasPreedit
    }

    /// Cancel the current conversion, reverting to hiragana.
    func cancel() {
        var command = Mozc_Commands_SessionCommand()
        command.type = .revert

        _ = client.sendCommand(command)
        currentCandidateStrings = []
        isConverting = false
    }

    /// Reset all state (e.g., on mode switch or deactivate).
    func reset() {
        if isConverting || !currentCandidateStrings.isEmpty {
            cancel()
        }
        currentCandidateStrings = []
        originalHiragana = ""
        isConverting = false
    }

    // MARK: - Private

    private func extractCandidates(from output: Mozc_Commands_Output) {
        var candidates: [String] = []

        if output.hasAllCandidateWords {
            for candidate in output.allCandidateWords.candidates {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(candidate.value)
                }
            }
        }

        if candidates.isEmpty, output.hasCandidateWindow {
            for candidate in output.candidateWindow.candidate {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(candidate.value)
                }
            }
        }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        if candidates.isEmpty, output.hasPreedit {
            let text = output.preedit.segment.map { $0.value }.joined()
            if !text.isEmpty {
                candidates.append(text)
            }
            if !originalHiragana.isEmpty && text != originalHiragana {
                candidates.append(originalHiragana)
            }
        }

        currentCandidateStrings = candidates
    }

    deinit {
        client.deleteSession()
        serverManager.shutdownServer()
    }
}
