import Foundation
import InputMethodKit

/// Manages Mozc conversion state and candidate display.
/// Follows the same pattern as HanjaConverter for IMKCandidates integration.
final class MozcConverter {
    private let client = MozcClient()
    private let serverManager = MozcServerManager()

    /// Current candidate strings for IMKCandidates display.
    var currentCandidateStrings: [String] = []

    /// The original hiragana text being converted.
    var originalHiragana: String = ""

    /// Whether Mozc server is available.
    private(set) var isAvailable = false

    // MARK: - Conversion

    /// Convert hiragana to kanji candidates via Mozc.
    /// Returns true if candidates were found.
    func convert(hiragana: String) -> Bool {
        currentCandidateStrings = []
        originalHiragana = hiragana

        // Ensure server is running
        guard serverManager.ensureServerRunning() else {
            isAvailable = false
            return false
        }
        isAvailable = true

        // Send each hiragana character as a key event to build composition
        for char in hiragana {
            var keyEvent = Mozc_Commands_KeyEvent()
            keyEvent.keyString = String(char)

            guard let output = client.sendKey(keyEvent) else {
                client.resetSession()
                return false
            }

            if output.hasErrorCode {
                client.resetSession()
                return false
            }
        }

        // Send Space to trigger conversion
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space

        guard let output = client.sendKey(spaceKey) else {
            client.resetSession()
            return false
        }

        // Extract candidates from output
        extractCandidates(from: output)

        return !currentCandidateStrings.isEmpty
    }

    /// Select a candidate by index and return the committed text.
    func selectCandidate(at index: Int) -> String? {
        // Send SELECT_CANDIDATE command
        var command = Mozc_Commands_SessionCommand()
        command.type = .selectCandidate
        command.id = Int32(index)

        guard let output = client.sendCommand(command) else {
            return nil
        }

        // Then submit
        var submitCmd = Mozc_Commands_SessionCommand()
        submitCmd.type = .submit

        let submitOutput = client.sendCommand(submitCmd)

        // Get committed text from result
        if let result = submitOutput?.result, result.hasValue {
            currentCandidateStrings = []
            return result.value
        }

        // Fallback: if the output from selectCandidate has a result
        if output.hasResult, output.result.hasValue {
            currentCandidateStrings = []
            return output.result.value
        }

        // Fallback: get the text from preedit
        if let preedit = submitOutput?.preedit ?? (output.hasPreedit ? output.preedit : nil) {
            let text = preedit.segment.map { $0.value }.joined()
            if !text.isEmpty {
                currentCandidateStrings = []
                return text
            }
        }

        return nil
    }

    /// Cancel the current conversion, reverting to hiragana.
    func cancel() {
        var command = Mozc_Commands_SessionCommand()
        command.type = .revert

        _ = client.sendCommand(command)
        currentCandidateStrings = []
    }

    /// Reset all state (e.g., on mode switch or deactivate).
    func reset() {
        if !currentCandidateStrings.isEmpty {
            cancel()
        }
        currentCandidateStrings = []
        originalHiragana = ""
    }

    // MARK: - Private

    private func extractCandidates(from output: Mozc_Commands_Output) {
        var candidates: [String] = []

        // Try all_candidate_words first (comprehensive list)
        if output.hasAllCandidateWords {
            for candidate in output.allCandidateWords.candidates {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(candidate.value)
                }
            }
        }

        // Fallback: try candidates from candidate window
        if candidates.isEmpty, output.hasCandidateWindow {
            for candidate in output.candidateWindow.candidate {
                if candidate.hasValue && !candidate.value.isEmpty {
                    candidates.append(candidate.value)
                }
            }
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        // Fallback: use preedit segments as the first "candidate"
        if candidates.isEmpty, output.hasPreedit {
            let text = output.preedit.segment.map { $0.value }.joined()
            if !text.isEmpty {
                candidates.append(text)
            }
            // Also add the original hiragana as a fallback candidate
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
