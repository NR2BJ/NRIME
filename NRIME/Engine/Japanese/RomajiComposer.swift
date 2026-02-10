import Foundation

/// Result of a romaji input operation.
struct RomajiResult {
    /// Fully composed kana ready for display as marked text.
    let composing: String
    /// Pending romaji characters (not yet converted to kana).
    let pending: String
    /// Text that was committed (e.g., on Enter).
    let committed: String
}

/// Converts romaji keystrokes to hiragana in real time.
/// Maintains a composing buffer (converted kana) and a pending buffer (incomplete romaji).
final class RomajiComposer {

    /// Accumulated kana from completed romaji sequences.
    private(set) var composedKana: String = ""

    /// Romaji characters waiting for completion.
    private(set) var pendingRomaji: String = ""

    /// Whether there is any composing or pending text.
    var isComposing: Bool {
        !composedKana.isEmpty || !pendingRomaji.isEmpty
    }

    /// The full display text for marked text: composed kana + pending romaji.
    var displayText: String {
        composedKana + pendingRomaji
    }

    // MARK: - Input

    /// Process a single romaji character. Returns the updated composing state.
    func input(_ char: Character) -> RomajiResult {
        let c = char.lowercased()
        pendingRomaji += c

        // Try to resolve pending romaji to kana
        resolve()

        return RomajiResult(composing: composedKana, pending: pendingRomaji, committed: "")
    }

    /// Commit all composing text (pending "n" becomes "ん").
    func flush() -> String {
        // Pending "n" at end → ん
        if pendingRomaji == "n" {
            composedKana += "ん"
            pendingRomaji = ""
        }
        let result = composedKana + pendingRomaji
        composedKana = ""
        pendingRomaji = ""
        return result
    }

    /// Delete the last character. Returns updated state.
    func deleteBackward() -> RomajiResult {
        if !pendingRomaji.isEmpty {
            pendingRomaji.removeLast()
        } else if !composedKana.isEmpty {
            composedKana.removeLast()
        }
        return RomajiResult(composing: composedKana, pending: pendingRomaji, committed: "")
    }

    /// Clear all state without committing.
    func clear() {
        composedKana = ""
        pendingRomaji = ""
    }

    // MARK: - Resolution

    private func resolve() {
        // Keep trying to convert pending romaji until no more progress
        var changed = true
        while changed && !pendingRomaji.isEmpty {
            changed = false

            // 1. Exact match in romaji table (including "nn" → ん)
            if let kana = Self.romajiTable[pendingRomaji] {
                composedKana += kana
                pendingRomaji = ""
                changed = true
                continue
            }

            // 2. Sokuon (っ): double consonant (not "nn", handled by table above)
            if pendingRomaji.count >= 2 {
                let chars = Array(pendingRomaji)
                let first = chars[0]
                let second = chars[1]
                if first == second && first != "n" && Self.sokuonConsonants.contains(first) {
                    composedKana += "っ"
                    pendingRomaji = String(pendingRomaji.dropFirst())
                    changed = true
                    continue
                }
            }

            // 3. "n" followed by a consonant (not "n", "y", or a vowel) → ん
            if pendingRomaji.count >= 2 && pendingRomaji.first == "n" {
                let second = pendingRomaji[pendingRomaji.index(after: pendingRomaji.startIndex)]
                if !Self.vowels.contains(second) && second != "n" && second != "y" {
                    composedKana += "ん"
                    pendingRomaji = String(pendingRomaji.dropFirst())
                    changed = true
                    continue
                }
            }

            // 4. Check if any table entry starts with pending (partial match → wait)
            let hasPartialMatch = Self.romajiTable.keys.contains { $0.hasPrefix(pendingRomaji) }
            if hasPartialMatch {
                break // Wait for more input
            }

            // 5. No match and no partial match: try consuming first character
            //    This handles invalid sequences by passing through
            if pendingRomaji.count > 1 {
                // Try if removing first char and keeping rest helps
                let firstChar = pendingRomaji.removeFirst()
                composedKana += String(firstChar)
                changed = true
            } else {
                // Single unrecognized character — keep in pending
                break
            }
        }
    }

    // MARK: - Romaji Table

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    /// Consonants that can trigger sokuon (っ) when doubled
    private static let sokuonConsonants: Set<Character> = [
        "k", "s", "t", "p", "g", "z", "d", "b", "f", "j", "v", "w", "r", "h", "m"
    ]

    /// Complete romaji → hiragana mapping table
    static let romajiTable: [String: String] = [
        // Vowels
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",

        // K-row
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",

        // S-row
        "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",

        // T-row
        "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",

        // N-row
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",

        // H-row
        "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ",

        // M-row
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",

        // Y-row
        "ya": "や", "yu": "ゆ", "yo": "よ",

        // R-row
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",

        // W-row
        "wa": "わ", "wi": "ゐ", "we": "ゑ", "wo": "を",

        // N
        "nn": "ん", "xn": "ん",

        // Dakuten (voiced) - G
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",

        // Dakuten - Z
        "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",

        // Dakuten - D
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",

        // Dakuten - B
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",

        // Handakuten - P
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",

        // Youon (contracted sounds) - KY
        "kya": "きゃ", "kyi": "きぃ", "kyu": "きゅ", "kye": "きぇ", "kyo": "きょ",

        // GY
        "gya": "ぎゃ", "gyi": "ぎぃ", "gyu": "ぎゅ", "gye": "ぎぇ", "gyo": "ぎょ",

        // SH
        "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
        "sya": "しゃ", "syi": "しぃ", "syu": "しゅ", "sye": "しぇ", "syo": "しょ",

        // J
        "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
        "jya": "じゃ", "jyi": "じぃ", "jyu": "じゅ", "jye": "じぇ", "jyo": "じょ",
        "zya": "じゃ", "zyi": "じぃ", "zyu": "じゅ", "zye": "じぇ", "zyo": "じょ",

        // CH
        "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
        "tya": "ちゃ", "tyi": "ちぃ", "tyu": "ちゅ", "tye": "ちぇ", "tyo": "ちょ",
        "cya": "ちゃ", "cyu": "ちゅ", "cyo": "ちょ",

        // NY
        "nya": "にゃ", "nyi": "にぃ", "nyu": "にゅ", "nye": "にぇ", "nyo": "にょ",

        // HY
        "hya": "ひゃ", "hyi": "ひぃ", "hyu": "ひゅ", "hye": "ひぇ", "hyo": "ひょ",

        // BY
        "bya": "びゃ", "byi": "びぃ", "byu": "びゅ", "bye": "びぇ", "byo": "びょ",

        // PY
        "pya": "ぴゃ", "pyi": "ぴぃ", "pyu": "ぴゅ", "pye": "ぴぇ", "pyo": "ぴょ",

        // MY
        "mya": "みゃ", "myi": "みぃ", "myu": "みゅ", "mye": "みぇ", "myo": "みょ",

        // RY
        "rya": "りゃ", "ryi": "りぃ", "ryu": "りゅ", "rye": "りぇ", "ryo": "りょ",

        // F-combinations
        "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ",

        // T-combinations
        "tha": "てゃ", "thi": "てぃ", "thu": "てゅ", "the": "てぇ", "tho": "てょ",
        "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",

        // D-combinations
        "dha": "でゃ", "dhi": "でぃ", "dhu": "でゅ", "dhe": "でぇ", "dho": "でょ",
        "dwa": "どぁ", "dwi": "どぃ", "dwu": "どぅ", "dwe": "どぇ", "dwo": "どぉ",

        // W-combinations
        "wha": "うぁ", "whi": "うぃ", "whu": "う", "whe": "うぇ", "who": "うぉ",

        // V-combinations
        "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",

        // Small kana
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ",
        "xtu": "っ", "xtsu": "っ",
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
        "ltu": "っ", "ltsu": "っ",
        "lwa": "ゎ", "xwa": "ゎ",
        "lka": "ゕ", "xka": "ゕ",
        "lke": "ゖ", "xke": "ゖ",

        // Punctuation
        "-": "ー",
    ]
}
