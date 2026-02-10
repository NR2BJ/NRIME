import Foundation

// MARK: - Jamo Classification

enum JamoType {
    case consonant
    case vowel
}

struct Jamo {
    let type: JamoType
    let value: Character     // The actual jamo character (e.g., 'ㄱ', 'ㅏ')
    let onsetIndex: Int?     // Index in the 19-element onset table (nil if vowel)
    let nucleusIndex: Int?   // Index in the 21-element nucleus table (nil if consonant)
    let codaIndex: Int?      // Index in the 28-element coda table (nil if cannot be coda)
}

// MARK: - JamoTable

enum JamoTable {

    // MARK: - QWERTY Character to Jamo Mapping

    /// Maps a QWERTY character (from event.characters) to its Jamo info.
    /// Uses the unshifted character for base keys, shifted for double consonants and ㅒ/ㅖ.
    static func jamo(for character: Character) -> Jamo? {
        return qwertyMap[character]
    }

    // MARK: - Onset (초성) Table — 19 entries

    /// Onset jamo ordered by Unicode Hangul onset index (0-18).
    static let onsets: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ",
        "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    // MARK: - Nucleus (중성) Table — 21 entries

    /// Nucleus jamo ordered by Unicode Hangul nucleus index (0-20).
    static let nuclei: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ",
        "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ",
        "ㅡ", "ㅢ", "ㅣ"
    ]

    // MARK: - Coda (종성) Table — 28 entries (0 = no coda)

    /// Coda jamo ordered by Unicode Hangul coda index (1-27). Index 0 = no coda.
    /// The Character at index i corresponds to coda index (i+1).
    static let codas: [Character] = [
        "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ",
        "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ",
        "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ",
        "ㅌ", "ㅍ", "ㅎ"
    ]

    // MARK: - Consonant to Onset Index

    static let consonantToOnsetIndex: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (i, c) in onsets.enumerated() {
            map[c] = i
        }
        return map
    }()

    // MARK: - Consonant to Coda Index

    /// Maps a single consonant jamo to its coda index (1-27).
    /// Double consonants ㄸ(4), ㅃ(8), ㅉ(13) cannot be codas, so they are excluded.
    static let consonantToCodaIndex: [Character: Int] = [
        "ㄱ": 1, "ㄲ": 2, "ㄴ": 4, "ㄷ": 7, "ㄹ": 8,
        "ㅁ": 16, "ㅂ": 17, "ㅅ": 19, "ㅆ": 20, "ㅇ": 21,
        "ㅈ": 22, "ㅊ": 23, "ㅋ": 24, "ㅌ": 25, "ㅍ": 26, "ㅎ": 27
    ]

    // MARK: - Can Be Coda?

    static func canBeCoda(_ consonant: Character) -> Bool {
        return consonantToCodaIndex[consonant] != nil
    }

    // MARK: - Compound Vowels

    /// Maps (first nucleus index, second nucleus index) → compound nucleus index.
    static let compoundVowels: [Int: [Int: Int]] = [
        8:  [0: 9, 1: 10, 20: 11],    // ㅗ + ㅏ=ㅘ, ㅐ=ㅙ, ㅣ=ㅚ
        13: [4: 14, 5: 15, 20: 16],    // ㅜ + ㅓ=ㅝ, ㅔ=ㅞ, ㅣ=ㅟ
        18: [20: 19],                    // ㅡ + ㅣ=ㅢ
    ]

    /// Given a current nucleus index and a new vowel's nucleus index,
    /// returns the compound nucleus index if one exists.
    static func compoundNucleus(first: Int, second: Int) -> Int? {
        return compoundVowels[first]?[second]
    }

    /// Decompose a compound nucleus index to (first, second) nucleus indices.
    static let compoundVowelDecomposition: [Int: (first: Int, second: Int)] = [
        9: (8, 0),    // ㅘ → ㅗ + ㅏ
        10: (8, 1),   // ㅙ → ㅗ + ㅐ
        11: (8, 20),  // ㅚ → ㅗ + ㅣ
        14: (13, 4),  // ㅝ → ㅜ + ㅓ
        15: (13, 5),  // ㅞ → ㅜ + ㅔ
        16: (13, 20), // ㅟ → ㅜ + ㅣ
        19: (18, 20), // ㅢ → ㅡ + ㅣ
    ]

    // MARK: - Compound Codas

    /// Maps (first coda index, second consonant's coda index) → compound coda index.
    static let compoundCodas: [Int: [Int: Int]] = [
        1:  [19: 3],                                          // ㄱ + ㅅ = ㄳ
        4:  [22: 5, 27: 6],                                   // ㄴ + ㅈ = ㄵ, ㅎ = ㄶ
        8:  [1: 9, 16: 10, 17: 11, 19: 12, 25: 13, 26: 14, 27: 15], // ㄹ + ...
        17: [19: 18],                                         // ㅂ + ㅅ = ㅄ
    ]

    /// Given a current coda index and a new consonant's coda index,
    /// returns the compound coda index if one exists.
    static func compoundCoda(first: Int, second: Int) -> Int? {
        return compoundCodas[first]?[second]
    }

    /// Decompose a compound coda index to (first coda index, second coda index).
    /// The second index is a simple consonant coda index.
    static let compoundCodaDecomposition: [Int: (first: Int, second: Int)] = [
        3: (1, 19),   // ㄳ → ㄱ + ㅅ
        5: (4, 22),   // ㄵ → ㄴ + ㅈ
        6: (4, 27),   // ㄶ → ㄴ + ㅎ
        9: (8, 1),    // ㄺ → ㄹ + ㄱ
        10: (8, 16),  // ㄻ → ㄹ + ㅁ
        11: (8, 17),  // ㄼ → ㄹ + ㅂ
        12: (8, 19),  // ㄽ → ㄹ + ㅅ
        13: (8, 25),  // ㄾ → ㄹ + ㅌ
        14: (8, 26),  // ㄿ → ㄹ + ㅍ
        15: (8, 27),  // ㅀ → ㄹ + ㅎ
        18: (17, 19), // ㅄ → ㅂ + ㅅ
    ]

    // MARK: - Coda to Onset Conversion

    /// When a coda is split off to become the onset of the next syllable,
    /// convert a coda index to the corresponding onset index.
    static let codaToOnsetIndex: [Int: Int] = [
        1: 0,    // ㄱ
        2: 1,    // ㄲ
        4: 2,    // ㄴ
        7: 3,    // ㄷ
        8: 5,    // ㄹ
        16: 6,   // ㅁ
        17: 7,   // ㅂ
        19: 9,   // ㅅ
        20: 10,  // ㅆ
        21: 11,  // ㅇ
        22: 12,  // ㅈ
        23: 14,  // ㅊ
        24: 15,  // ㅋ
        25: 16,  // ㅌ
        26: 17,  // ㅍ
        27: 18,  // ㅎ
    ]

    // MARK: - Compatibility Jamo for Display

    /// Unicode compatibility jamo for displaying a standalone onset consonant.
    /// Maps onset index → Unicode scalar value in the compatibility jamo block (U+3131-U+314E).
    static let onsetToCompatibilityJamo: [Int: UInt32] = [
        0: 0x3131,  // ㄱ
        1: 0x3132,  // ㄲ
        2: 0x3134,  // ㄴ
        3: 0x3137,  // ㄷ
        4: 0x3138,  // ㄸ
        5: 0x3139,  // ㄹ
        6: 0x3141,  // ㅁ
        7: 0x3142,  // ㅂ
        8: 0x3143,  // ㅃ
        9: 0x3145,  // ㅅ
        10: 0x3146, // ㅆ
        11: 0x3147, // ㅇ
        12: 0x3148, // ㅈ
        13: 0x3149, // ㅉ
        14: 0x314A, // ㅊ
        15: 0x314B, // ㅋ
        16: 0x314C, // ㅌ
        17: 0x314D, // ㅍ
        18: 0x314E, // ㅎ
    ]

    // MARK: - Unicode Hangul Composition

    static let hangulBase: UInt32 = 0xAC00
    static let onsetCount: UInt32 = 19
    static let nucleusCount: UInt32 = 21
    static let codaCount: UInt32 = 28

    /// Compose a complete Hangul syllable from onset, nucleus, and coda indices.
    static func composeSyllable(onset: Int, nucleus: Int, coda: Int = 0) -> String {
        let code = UInt32(onset) * nucleusCount * codaCount
            + UInt32(nucleus) * codaCount
            + UInt32(coda)
            + hangulBase
        return String(Unicode.Scalar(code)!)
    }

    /// Return the compatibility jamo character for a standalone onset consonant.
    static func onsetString(index: Int) -> String {
        guard let scalar = onsetToCompatibilityJamo[index] else { return "" }
        return String(Unicode.Scalar(scalar)!)
    }

    // MARK: - QWERTY Mapping Table (Private)

    private static let qwertyMap: [Character: Jamo] = {
        var m: [Character: Jamo] = [:]

        // Helper to create consonant entries
        func c(_ char: Character, _ jamoChar: Character, onset: Int, coda: Int?) {
            m[char] = Jamo(
                type: .consonant, value: jamoChar,
                onsetIndex: onset, nucleusIndex: nil, codaIndex: coda
            )
        }

        // Helper to create vowel entries
        func v(_ char: Character, _ jamoChar: Character, nucleus: Int) {
            m[char] = Jamo(
                type: .vowel, value: jamoChar,
                onsetIndex: nil, nucleusIndex: nucleus, codaIndex: nil
            )
        }

        // Consonants (left side of keyboard)
        c("r", "ㄱ", onset: 0,  coda: 1)
        c("R", "ㄲ", onset: 1,  coda: 2)
        c("s", "ㄴ", onset: 2,  coda: 4)
        c("e", "ㄷ", onset: 3,  coda: 7)
        c("E", "ㄸ", onset: 4,  coda: nil) // Cannot be coda
        c("f", "ㄹ", onset: 5,  coda: 8)
        c("a", "ㅁ", onset: 6,  coda: 16)
        c("q", "ㅂ", onset: 7,  coda: 17)
        c("Q", "ㅃ", onset: 8,  coda: nil) // Cannot be coda
        c("t", "ㅅ", onset: 9,  coda: 19)
        c("T", "ㅆ", onset: 10, coda: 20)
        c("d", "ㅇ", onset: 11, coda: 21)
        c("w", "ㅈ", onset: 12, coda: 22)
        c("W", "ㅉ", onset: 13, coda: nil) // Cannot be coda
        c("c", "ㅊ", onset: 14, coda: 23)
        c("z", "ㅋ", onset: 15, coda: 24)
        c("x", "ㅌ", onset: 16, coda: 25)
        c("v", "ㅍ", onset: 17, coda: 26)
        c("g", "ㅎ", onset: 18, coda: 27)

        // Vowels (right side of keyboard)
        v("k", "ㅏ", nucleus: 0)
        v("o", "ㅐ", nucleus: 1)
        v("i", "ㅑ", nucleus: 2)
        v("O", "ㅒ", nucleus: 3)
        v("j", "ㅓ", nucleus: 4)
        v("p", "ㅔ", nucleus: 5)
        v("u", "ㅕ", nucleus: 6)
        v("P", "ㅖ", nucleus: 7)
        v("h", "ㅗ", nucleus: 8)
        v("y", "ㅛ", nucleus: 12)
        v("n", "ㅜ", nucleus: 13)
        v("b", "ㅠ", nucleus: 17)
        v("m", "ㅡ", nucleus: 18)
        v("l", "ㅣ", nucleus: 20)

        return m
    }()
}
