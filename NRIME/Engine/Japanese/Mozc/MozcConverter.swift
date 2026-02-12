import Foundation
import InputMethodKit

/// Result of processing a Mozc Output.
struct MozcResult {
    var committedText: String? = nil
    var preedit: Mozc_Commands_Preedit? = nil
    var hasCandidates: Bool = false
    var consumed: Bool = true
    var focusedCandidateIndex: Int = 0
    var candidateCategory: Mozc_Commands_Category = .conversion
}

/// A candidate with its Mozc ID for SELECT_CANDIDATE commands.
struct MozcCandidate {
    let value: String
    let id: Int32
}

/// Manages Mozc conversion state and candidate display.
final class MozcConverter {
    private let client = MozcClient()
    private let serverManager = MozcServerManager()

    /// Current candidate strings for CandidatePanel display.
    var currentCandidateStrings: [String] = []

    /// Current candidates with Mozc IDs (for number-key selection).
    private(set) var currentCandidates: [MozcCandidate] = []

    /// The latest preedit from Mozc (multi-segment data after conversion).
    private(set) var currentPreedit: Mozc_Commands_Preedit? = nil

    /// The original hiragana text being converted.
    var originalHiragana: String = ""

    /// Whether Mozc server is available.
    private(set) var isAvailable = false

    /// Whether Mozc currently has an active conversion (segments in preedit).
    private(set) var isConverting: Bool = false

    /// The currently focused candidate index from Mozc's candidate window.
    private(set) var currentFocusedIndex: Int = 0

    /// The last Output returned by feedHiragana (for live conversion).
    private(set) var lastFeedOutput: Mozc_Commands_Output? = nil

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
    /// The last character's Output is stored in `lastFeedOutput` for live conversion.
    func feedHiragana(_ hiragana: String) -> Bool {
        guard serverManager.ensureServerRunning() else {
            isAvailable = false
            return false
        }
        isAvailable = true
        lastFeedOutput = nil

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
                lastFeedOutput = output
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
            currentPreedit = output.preedit
            isConverting = true
        } else {
            currentPreedit = nil
            isConverting = false
        }

        // 3. Extract candidates and category
        extractCandidates(from: output)
        result.hasCandidates = !currentCandidateStrings.isEmpty

        if output.hasAllCandidateWords, output.allCandidateWords.hasCategory {
            result.candidateCategory = output.allCandidateWords.category
        } else if output.hasCandidateWindow, output.candidateWindow.hasCategory {
            result.candidateCategory = output.candidateWindow.category
        }

        // 4. Extract focused candidate index
        if output.hasAllCandidateWords, output.allCandidateWords.hasFocusedIndex {
            currentFocusedIndex = Int(output.allCandidateWords.focusedIndex)
        } else if output.hasCandidateWindow, output.candidateWindow.hasFocusedIndex {
            currentFocusedIndex = Int(output.candidateWindow.focusedIndex)
        }
        result.focusedCandidateIndex = currentFocusedIndex

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
        currentCandidates = []
        currentPreedit = nil
        currentFocusedIndex = 0

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
        currentCandidates = []
        currentPreedit = nil
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

        let result = updateFromOutput(output!)
        return result.hasCandidates || result.preedit != nil
    }

    /// Convert hiragana already fed to Mozc by sending Space.
    /// Used by live conversion when hiragana is already in Mozc's composition state.
    func convertAlreadyFed() -> Bool {
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space

        guard let output = client.sendKey(spaceKey) else { return false }

        let result = updateFromOutput(output)
        return result.hasCandidates || result.preedit != nil
    }

    /// Peek at the conversion result without committing.
    /// Sends Space to trigger conversion, reads the preedit (which now contains kanji segments).
    /// After this call, the Mozc session is in CONVERSION state (not reverted).
    /// The caller should call cancel() before the next feedHiragana() if needed.
    func peekConversion() -> String? {
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space

        guard let output = client.sendKey(spaceKey) else { return nil }

        if output.hasPreedit, !output.preedit.segment.isEmpty {
            currentPreedit = output.preedit
            isConverting = true
            // Also extract candidates for when user presses Space to see full list
            extractCandidates(from: output)
            return output.preedit.segment.map { $0.value }.joined()
        }

        return nil
    }

    /// Cancel the current conversion, reverting to hiragana.
    func cancel() {
        var command = Mozc_Commands_SessionCommand()
        command.type = .revert

        _ = client.sendCommand(command)
        currentCandidateStrings = []
        currentCandidates = []
        currentPreedit = nil
        currentFocusedIndex = 0
        isConverting = false
    }

    /// Clear Mozc's learned user history and prediction data.
    func clearUserHistory() {
        client.clearUserHistory()
        client.clearUserPrediction()
    }

    /// Reset all state (e.g., on mode switch or deactivate).
    func reset() {
        if isConverting || !currentCandidateStrings.isEmpty {
            cancel()
        }
        currentCandidateStrings = []
        currentCandidates = []
        currentPreedit = nil
        currentFocusedIndex = 0
        originalHiragana = ""
        isConverting = false
        lastFeedOutput = nil
    }

    // MARK: - Prediction

    /// Request next-word prediction from Mozc after committing text.
    /// `precedingText` is the text before the cursor (up to ~20 chars), used by Mozc's NWP engine.
    /// Returns a MozcResult with prediction candidates, or nil if none.
    func requestPrediction(precedingText: String = "") -> MozcResult? {
        var command = Mozc_Commands_SessionCommand()
        command.type = .requestNwp

        var context: Mozc_Commands_Context? = nil
        if !precedingText.isEmpty {
            var ctx = Mozc_Commands_Context()
            ctx.precedingText = precedingText
            context = ctx
        }

        guard let output = client.sendCommand(command, context: context) else { return nil }

        let result = updateFromOutput(output)
        return result.hasCandidates ? result : nil
    }

    // MARK: - Candidate Selection

    /// Select a candidate by its index using Mozc's SELECT_CANDIDATE command.
    /// Returns the output from Mozc after selection (may commit segment and advance to next).
    func selectCandidateByIndex(_ index: Int) -> Mozc_Commands_Output? {
        guard index >= 0 && index < currentCandidates.count else { return nil }

        let candidate = currentCandidates[index]
        var command = Mozc_Commands_SessionCommand()
        command.type = .selectCandidate
        command.id = candidate.id

        return client.sendCommand(command)
    }

    // MARK: - Private

    private func extractCandidates(from output: Mozc_Commands_Output) {
        var candidates: [MozcCandidate] = []

        if output.hasAllCandidateWords {
            for candidate in output.allCandidateWords.candidates {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(MozcCandidate(value: candidate.value, id: candidate.id))
                }
            }
        }

        if candidates.isEmpty, output.hasCandidateWindow {
            for candidate in output.candidateWindow.candidate {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(MozcCandidate(value: candidate.value, id: candidate.id))
                }
            }
        }

        if candidates.isEmpty, output.hasPreedit {
            let text = output.preedit.segment.map { $0.value }.joined()
            if !text.isEmpty {
                candidates.append(MozcCandidate(value: text, id: 0))
            }
            if !originalHiragana.isEmpty && text != originalHiragana {
                candidates.append(MozcCandidate(value: originalHiragana, id: -1))
            }
        }

        currentCandidates = candidates
        currentCandidateStrings = candidates.map { $0.value }
    }

    deinit {
        client.deleteSession()
        serverManager.shutdownServer()
    }
}
