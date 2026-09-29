import Foundation
import InputMethodKit

/// Result of processing a Mozc Output.
struct MozcResult {
    var committedText: String? = nil
    var preedit: Mozc_Commands_Preedit? = nil
    var hasCandidates: Bool = false
    var consumed: Bool = true
    var focusedCandidateIndex: Int = 0
}

/// A candidate with its Mozc ID for SELECT_CANDIDATE commands.
struct MozcCandidate {
    let value: String
    let id: Int32
}

/// Manages Mozc conversion state and candidate display.
final class MozcConverter {
    private let client = MozcClient()

    /// Current candidate strings for CandidatePanel display.
    var currentCandidateStrings: [String] = []

    /// Current candidates with Mozc IDs (for number-key selection).
    private(set) var currentCandidates: [MozcCandidate] = []

    /// The latest preedit from Mozc (multi-segment data after conversion).
    private(set) var currentPreedit: Mozc_Commands_Preedit? = nil

    /// The original hiragana text being converted.
    var originalHiragana: String = ""

    /// Whether Mozc currently has an active conversion (segments in preedit).
    private(set) var isConverting: Bool = false

    /// The currently focused candidate index from Mozc's candidate window.
    private(set) var currentFocusedIndex: Int = 0

    // MARK: - Key Forwarding API

    /// Forward a key event to the active Mozc session.
    func sendKeyEvent(_ keyEvent: Mozc_Commands_KeyEvent) -> Mozc_Commands_Output? {
        return client.sendKey(keyEvent)
    }

    /// Feed hiragana characters to Mozc to build composition state (without triggering conversion).
    /// False when the engine is not running; the caller keeps the composition.
    func feedHiragana(_ hiragana: String) -> Bool {
        guard MozcEngine.shared.isAvailable else {
            DeveloperLogger.shared.log("MozcConvert", "feedHiragana skipped — Mozc engine not available")
            return false
        }

        let chars = Array(hiragana)
        var retried = false
        var i = 0

        while i < chars.count {
            var keyEvent = Mozc_Commands_KeyEvent()
            keyEvent.keyString = String(chars[i])

            let output = client.sendKey(keyEvent)

            if let output, !output.hasErrorCode {
                i += 1
            } else if output != nil, !retried {
                // Mozc answered with an error — a session it no longer has
                // (more than 64 sessions evict the least recently used one).
                // A fresh session is enough.
                DeveloperLogger.shared.log("MozcConvert", "feedHiragana got error code — resetting session and retrying")
                client.resetSession()
                retried = true
                i = 0
            } else if output == nil {
                DeveloperLogger.shared.log("MozcConvert", "feedHiragana got no answer")
                dropSession()
                return false
            } else {
                DeveloperLogger.shared.log("MozcConvert", "feedHiragana failed after retry")
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

        // 4. Extract focused candidate index
        if output.hasAllCandidateWords, output.allCandidateWords.hasFocusedIndex {
            currentFocusedIndex = Int(output.allCandidateWords.focusedIndex)
        } else if output.hasCandidateWindow, output.candidateWindow.hasFocusedIndex {
            currentFocusedIndex = Int(output.candidateWindow.focusedIndex)
        } else {
            currentFocusedIndex = 0
        }
        result.focusedCandidateIndex = currentFocusedIndex

        result.consumed = output.consumed
        return result
    }

    /// Submit the conversion and return the text to commit: Mozc's result or,
    /// when it gives none (a stale session), `fallback` — by default what is
    /// on screen. The word the user confirmed is never dropped or turned back
    /// into its reading. Local state is cleared either way.
    func commit(fallback: String? = nil) -> String? {
        let onScreen = fallback ?? displayedText
        var command = Mozc_Commands_SessionCommand()
        command.type = .submit
        let output = client.sendCommand(command)
        if output == nil {
            dropSession()
        }
        discardLocalState()
        if let output, output.hasResult, !output.result.value.isEmpty {
            return output.result.value
        }
        return onScreen
    }

    /// The conversion as it is displayed: its segments, else the reading.
    var displayedText: String? {
        Self.displayedText(preedit: currentPreedit, reading: originalHiragana)
    }

    static func displayedText(preedit: Mozc_Commands_Preedit?, reading: String) -> String? {
        if let preedit, !preedit.segment.isEmpty {
            let text = preedit.segment.map(\.value).joined()
            if !text.isEmpty {
                return text
            }
        }
        return reading.isEmpty ? nil : reading
    }

    /// Mozc gave no answer — the engine is not running. Forget the session;
    /// the next command starts a new one once it is.
    func dropSession() {
        client.forgetSession()
    }

    // MARK: - Conversion

    /// Convert hiragana to kanji candidates via Mozc.
    /// Returns true if conversion produced a preedit or candidates; false when
    /// the engine is not running or found nothing.
    func convert(hiragana: String) -> Bool {
        DeveloperLogger.shared.log("MozcConvert", "Convert requested",
                                   metadata: ["length": "\(hiragana.count)"])
        prepareForConversion(hiragana: hiragana)

        let feedOk = feedHiragana(hiragana)
        guard feedOk else { return false }

        // Send Space to trigger conversion
        var spaceKey = Mozc_Commands_KeyEvent()
        spaceKey.specialKey = .space

        guard let output = client.sendKey(spaceKey) else {
            dropSession()
            return false
        }

        let result = updateFromOutput(output)
        DeveloperLogger.shared.log("MozcConvert", "Convert result",
                                   metadata: ["candidates": "\(currentCandidateStrings.count)",
                                              "hasPreedit": "\(result.preedit != nil)"])
        return result.hasCandidates || result.preedit != nil
    }

    /// Reset per-conversion state and remember the source hiragana to support Escape restore.
    func prepareForConversion(hiragana: String) {
        currentCandidateStrings = []
        currentCandidates = []
        currentPreedit = nil
        currentFocusedIndex = 0
        isConverting = false
        originalHiragana = hiragana
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
    }

    /// Forget the conversion here without telling Mozc — it is unreachable,
    /// or has already been told. The session is sorted out on its next use.
    func discardLocalState() {
        currentCandidateStrings = []
        currentCandidates = []
        currentPreedit = nil
        currentFocusedIndex = 0
        originalHiragana = ""
        isConverting = false
    }

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

    /// Highlight a candidate by its index using Mozc's HIGHLIGHT_CANDIDATE command.
    /// Unlike selectCandidateByIndex, this does NOT commit — it only changes the focused candidate
    /// and updates the preedit display. Used to sync panel selection back to Mozc.
    func highlightCandidateByIndex(_ index: Int) -> Mozc_Commands_Output? {
        guard index >= 0 && index < currentCandidates.count else { return nil }

        let candidate = currentCandidates[index]
        var command = Mozc_Commands_SessionCommand()
        command.type = .highlightCandidate
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

        currentCandidates = candidates
        currentCandidateStrings = candidates.map { $0.value }
    }

    deinit {
        client.deleteSession()
    }
}
