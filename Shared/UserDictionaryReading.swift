import Foundation

/// The reading of a user-dictionary word, as Mozc stores it.
enum UserDictionaryReading {
    /// Trimmed, half-width katakana and full-width letters folded by NFKC, and
    /// katakana turned into hiragana (UserDictionaryUtil::NormalizeReading).
    /// Conversion looks words up by the hiragana the input method types, so a
    /// reading saved in katakana never matched. Foundation's katakana→hiragana
    /// transform is not used: it turns the long-vowel mark into a vowel
    /// (ヴぁー → ゔぁあ). Small kana (ゃ っ ぁ…) and ー stay as they are.
    static func normalized(_ text: String) -> String {
        let folded = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                out.append(hiragana)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}
