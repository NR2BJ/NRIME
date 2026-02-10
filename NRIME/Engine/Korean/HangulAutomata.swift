import Foundation

// MARK: - Hangul Automata Result

struct HangulResult {
    /// Text to commit (insert permanently). Empty if nothing to commit.
    let committed: String
    /// Text currently being composed (shown as marked/underlined text). Empty if no composition.
    let composing: String
}

// MARK: - FSM State

private enum HangulState {
    case empty                     // No jamo entered
    case onset                     // 초성 only (e.g., ㄱ)
    case onsetNucleus              // 초성+중성 (e.g., 가)
    case onsetNucleusCompound      // 초성+compound중성 (e.g., 과)
    case onsetNucleusCoda          // 초성+중성+종성 (e.g., 간)
    case onsetNucleusCompoundCoda  // 초성+중성+compound종성 (e.g., 값)
}

// MARK: - HangulAutomata

final class HangulAutomata {
    private var state: HangulState = .empty

    private var onset: Int = 0      // 초성 index (0-18)
    private var nucleus: Int = 0    // 중성 index (0-20)
    private var coda: Int = 0       // 종성 index (0-27, 0 = no coda)

    // For compound tracking (to support backspace decomposition)
    private var nucleusFirst: Int?  // First part of compound vowel
    private var codaFirst: Int?     // First part of compound coda

    /// Process a jamo input and return the result.
    func input(_ jamo: Jamo) -> HangulResult {
        switch jamo.type {
        case .consonant:
            return inputConsonant(jamo)
        case .vowel:
            return inputVowel(jamo)
        }
    }

    /// Handle backspace. Returns the updated composing text.
    func deleteBackward() -> HangulResult {
        switch state {
        case .empty:
            return HangulResult(committed: "", composing: "")

        case .onset:
            state = .empty
            return HangulResult(committed: "", composing: "")

        case .onsetNucleus:
            state = .onset
            return HangulResult(committed: "", composing: currentOnsetString())

        case .onsetNucleusCompound:
            // Revert to first vowel of compound
            if let first = nucleusFirst {
                nucleus = first
                nucleusFirst = nil
                state = .onsetNucleus
                return HangulResult(committed: "", composing: currentSyllable())
            }
            // Fallback: remove nucleus entirely
            state = .onset
            return HangulResult(committed: "", composing: currentOnsetString())

        case .onsetNucleusCoda:
            coda = 0
            codaFirst = nil
            // Determine correct nucleus state
            if JamoTable.compoundVowelDecomposition[nucleus] != nil {
                state = .onsetNucleusCompound
            } else {
                state = .onsetNucleus
            }
            return HangulResult(committed: "", composing: currentSyllable())

        case .onsetNucleusCompoundCoda:
            // Revert to first consonant of compound coda
            if let first = codaFirst {
                coda = first
                codaFirst = nil
                state = .onsetNucleusCoda
                return HangulResult(committed: "", composing: currentSyllable())
            }
            // Fallback: remove coda entirely
            coda = 0
            if JamoTable.compoundVowelDecomposition[nucleus] != nil {
                state = .onsetNucleusCompound
            } else {
                state = .onsetNucleus
            }
            return HangulResult(committed: "", composing: currentSyllable())
        }
    }

    /// Commit current composing text and reset.
    func flush() -> String {
        let text = currentComposingText()
        state = .empty
        onset = 0
        nucleus = 0
        coda = 0
        nucleusFirst = nil
        codaFirst = nil
        return text
    }

    /// Returns the current composing text without modifying state.
    func currentComposingText() -> String {
        switch state {
        case .empty:
            return ""
        case .onset:
            return currentOnsetString()
        default:
            return currentSyllable()
        }
    }

    /// Whether the automata has any composing state.
    var isComposing: Bool {
        return state != .empty
    }

    // MARK: - Consonant Input

    private func inputConsonant(_ jamo: Jamo) -> HangulResult {
        let onsetIdx = jamo.onsetIndex!
        let codaIdx = jamo.codaIndex

        switch state {
        case .empty:
            onset = onsetIdx
            state = .onset
            return HangulResult(committed: "", composing: currentOnsetString())

        case .onset:
            // Commit previous onset, start new onset
            let committed = currentOnsetString()
            onset = onsetIdx
            // state stays .onset
            return HangulResult(committed: committed, composing: currentOnsetString())

        case .onsetNucleus, .onsetNucleusCompound:
            if let codaIdx = codaIdx {
                // This consonant can be a coda — add it
                coda = codaIdx
                codaFirst = nil
                state = .onsetNucleusCoda
                return HangulResult(committed: "", composing: currentSyllable())
            } else {
                // Cannot be coda (ㄸ, ㅃ, ㅉ) — commit current syllable, start new onset
                let committed = currentSyllable()
                resetForNewOnset(onsetIdx)
                return HangulResult(committed: committed, composing: currentOnsetString())
            }

        case .onsetNucleusCoda:
            // Try to form compound coda
            if let codaIdx = codaIdx,
               let compound = JamoTable.compoundCoda(first: coda, second: codaIdx) {
                codaFirst = coda
                coda = compound
                state = .onsetNucleusCompoundCoda
                return HangulResult(committed: "", composing: currentSyllable())
            }
            // Cannot compound — commit current syllable, start new onset
            let committed = currentSyllable()
            resetForNewOnset(onsetIdx)
            return HangulResult(committed: committed, composing: currentOnsetString())

        case .onsetNucleusCompoundCoda:
            // Compound coda cannot extend further — commit and start new
            let committed = currentSyllable()
            resetForNewOnset(onsetIdx)
            return HangulResult(committed: committed, composing: currentOnsetString())
        }
    }

    // MARK: - Vowel Input

    private func inputVowel(_ jamo: Jamo) -> HangulResult {
        let nucleusIdx = jamo.nucleusIndex!

        switch state {
        case .empty:
            // Standalone vowel — commit immediately
            let vowelStr = JamoTable.composeSyllable(onset: 11, nucleus: nucleusIdx, coda: 0)
            // Actually, standalone vowels in Korean use ㅇ (ieung) as placeholder onset
            // But for a pure vowel without onset, we should use compatibility jamo
            // Let's use the ㅇ+vowel syllable since that's how Korean input methods work
            // Actually no — standalone vowel should just be the vowel character
            // The standard behavior: typing a vowel without onset shows the vowel
            // For display, use the compatibility vowel jamo
            let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
            return HangulResult(committed: nucleusScalar, composing: "")

        case .onset:
            // Onset + vowel → compose syllable
            nucleus = nucleusIdx
            coda = 0
            nucleusFirst = nil
            codaFirst = nil
            state = .onsetNucleus
            return HangulResult(committed: "", composing: currentSyllable())

        case .onsetNucleus:
            // Try to form compound vowel
            if let compound = JamoTable.compoundNucleus(first: nucleus, second: nucleusIdx) {
                nucleusFirst = nucleus
                nucleus = compound
                state = .onsetNucleusCompound
                return HangulResult(committed: "", composing: currentSyllable())
            }
            // Cannot compound — commit current syllable, handle vowel as standalone
            let committed = currentSyllable()
            state = .empty
            let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
            return HangulResult(committed: committed + nucleusScalar, composing: "")

        case .onsetNucleusCompound:
            // Compound vowel cannot extend further — commit and handle vowel
            let committed = currentSyllable()
            state = .empty
            let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
            return HangulResult(committed: committed + nucleusScalar, composing: "")

        case .onsetNucleusCoda:
            // Split: remove coda, commit syllable without it,
            // use coda as new onset + new vowel
            let splitCodaIdx = coda
            coda = 0

            let committed = currentSyllable()

            // Convert coda to onset for the new syllable
            guard let newOnsetIdx = JamoTable.codaToOnsetIndex[splitCodaIdx] else {
                // Shouldn't happen, but handle gracefully
                state = .empty
                let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
                return HangulResult(committed: committed + nucleusScalar, composing: "")
            }

            onset = newOnsetIdx
            nucleus = nucleusIdx
            nucleusFirst = nil
            codaFirst = nil
            state = .onsetNucleus
            return HangulResult(committed: committed, composing: currentSyllable())

        case .onsetNucleusCompoundCoda:
            // Split compound coda: keep first part, split off second part as new onset
            guard let decomposed = JamoTable.compoundCodaDecomposition[coda] else {
                // Fallback: treat like simple coda split
                let splitCodaIdx = coda
                coda = 0
                let committed = currentSyllable()

                guard let newOnsetIdx = JamoTable.codaToOnsetIndex[splitCodaIdx] else {
                    state = .empty
                    let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
                    return HangulResult(committed: committed + nucleusScalar, composing: "")
                }

                onset = newOnsetIdx
                nucleus = nucleusIdx
                nucleusFirst = nil
                codaFirst = nil
                state = .onsetNucleus
                return HangulResult(committed: committed, composing: currentSyllable())
            }

            // Keep first part as coda, commit that syllable
            coda = decomposed.first
            codaFirst = nil
            let committed = currentSyllable()

            // Second part becomes onset of new syllable
            guard let newOnsetIdx = JamoTable.codaToOnsetIndex[decomposed.second] else {
                state = .empty
                let nucleusScalar = nucleusToCompatibilityJamo(nucleusIdx)
                return HangulResult(committed: committed + nucleusScalar, composing: "")
            }

            onset = newOnsetIdx
            nucleus = nucleusIdx
            coda = 0
            nucleusFirst = nil
            codaFirst = nil
            state = .onsetNucleus
            return HangulResult(committed: committed, composing: currentSyllable())
        }
    }

    // MARK: - Helpers

    private func currentSyllable() -> String {
        return JamoTable.composeSyllable(onset: onset, nucleus: nucleus, coda: coda)
    }

    private func currentOnsetString() -> String {
        return JamoTable.onsetString(index: onset)
    }

    private func resetForNewOnset(_ onsetIdx: Int) {
        onset = onsetIdx
        nucleus = 0
        coda = 0
        nucleusFirst = nil
        codaFirst = nil
        state = .onset
    }

    private func nucleusToCompatibilityJamo(_ nucleusIdx: Int) -> String {
        // Compatibility jamo for vowels: U+314F (ㅏ) to U+3163 (ㅣ)
        let base: UInt32 = 0x314F
        let scalar = base + UInt32(nucleusIdx)
        return String(Unicode.Scalar(scalar)!)
    }
}
