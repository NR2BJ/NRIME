import XCTest
@testable import NRIME

final class JamoTableTests: XCTestCase {

    // MARK: - QWERTY Mapping

    func testConsonantMappings() {
        // Verify a few key consonant mappings
        let r = JamoTable.jamo(for: "r")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.type, .consonant)
        XCTAssertEqual(r?.value, "ㄱ")
        XCTAssertEqual(r?.onsetIndex, 0)
        XCTAssertEqual(r?.codaIndex, 1)

        let t = JamoTable.jamo(for: "t")
        XCTAssertEqual(t?.value, "ㅅ")
        XCTAssertEqual(t?.onsetIndex, 9)
        XCTAssertEqual(t?.codaIndex, 19)

        let g = JamoTable.jamo(for: "g")
        XCTAssertEqual(g?.value, "ㅎ")
        XCTAssertEqual(g?.onsetIndex, 18)
        XCTAssertEqual(g?.codaIndex, 27)
    }

    func testVowelMappings() {
        let k = JamoTable.jamo(for: "k")
        XCTAssertNotNil(k)
        XCTAssertEqual(k?.type, .vowel)
        XCTAssertEqual(k?.value, "ㅏ")
        XCTAssertEqual(k?.nucleusIndex, 0)

        let h = JamoTable.jamo(for: "h")
        XCTAssertEqual(h?.value, "ㅗ")
        XCTAssertEqual(h?.nucleusIndex, 8)

        let l = JamoTable.jamo(for: "l")
        XCTAssertEqual(l?.value, "ㅣ")
        XCTAssertEqual(l?.nucleusIndex, 20)
    }

    func testDoubleConsonants() {
        let shiftR = JamoTable.jamo(for: "R")
        XCTAssertEqual(shiftR?.value, "ㄲ")
        XCTAssertEqual(shiftR?.onsetIndex, 1)
        XCTAssertEqual(shiftR?.codaIndex, 2) // ㄲ can be coda

        let shiftE = JamoTable.jamo(for: "E")
        XCTAssertEqual(shiftE?.value, "ㄸ")
        XCTAssertNil(shiftE?.codaIndex) // ㄸ cannot be coda

        let shiftQ = JamoTable.jamo(for: "Q")
        XCTAssertEqual(shiftQ?.value, "ㅃ")
        XCTAssertNil(shiftQ?.codaIndex) // ㅃ cannot be coda

        let shiftW = JamoTable.jamo(for: "W")
        XCTAssertEqual(shiftW?.value, "ㅉ")
        XCTAssertNil(shiftW?.codaIndex) // ㅉ cannot be coda
    }

    func testSpecialVowels() {
        let shiftO = JamoTable.jamo(for: "O")
        XCTAssertEqual(shiftO?.value, "ㅒ")
        XCTAssertEqual(shiftO?.nucleusIndex, 3)

        let shiftP = JamoTable.jamo(for: "P")
        XCTAssertEqual(shiftP?.value, "ㅖ")
        XCTAssertEqual(shiftP?.nucleusIndex, 7)
    }

    func testNonJamoReturnsNil() {
        XCTAssertNil(JamoTable.jamo(for: "1"))
        XCTAssertNil(JamoTable.jamo(for: " "))
        XCTAssertNil(JamoTable.jamo(for: "."))
        XCTAssertNil(JamoTable.jamo(for: "A"))
    }

    // MARK: - All 33 Jamo Covered

    func testAll19Consonants() {
        let consonantKeys: [Character] = ["r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g"]
        for key in consonantKeys {
            let jamo = JamoTable.jamo(for: key)
            XCTAssertNotNil(jamo, "Missing mapping for '\(key)'")
            XCTAssertEqual(jamo?.type, .consonant, "'\(key)' should be consonant")
            XCTAssertNotNil(jamo?.onsetIndex, "'\(key)' should have onset index")
        }
    }

    func testAll14Vowels() {
        let vowelKeys: [Character] = ["k", "o", "i", "O", "j", "p", "u", "P", "h", "y", "n", "b", "m", "l"]
        for key in vowelKeys {
            let jamo = JamoTable.jamo(for: key)
            XCTAssertNotNil(jamo, "Missing mapping for '\(key)'")
            XCTAssertEqual(jamo?.type, .vowel, "'\(key)' should be vowel")
            XCTAssertNotNil(jamo?.nucleusIndex, "'\(key)' should have nucleus index")
        }
    }

    // MARK: - canBeCoda

    func testCanBeCoda() {
        XCTAssertTrue(JamoTable.canBeCoda("ㄱ"))
        XCTAssertTrue(JamoTable.canBeCoda("ㄴ"))
        XCTAssertTrue(JamoTable.canBeCoda("ㅎ"))
        XCTAssertFalse(JamoTable.canBeCoda("ㄸ"))
        XCTAssertFalse(JamoTable.canBeCoda("ㅃ"))
        XCTAssertFalse(JamoTable.canBeCoda("ㅉ"))
    }

    // MARK: - Compound Tables

    func testCompoundVowels() {
        // ㅗ + ㅏ = ㅘ
        XCTAssertEqual(JamoTable.compoundNucleus(first: 8, second: 0), 9)
        // ㅜ + ㅓ = ㅝ
        XCTAssertEqual(JamoTable.compoundNucleus(first: 13, second: 4), 14)
        // ㅡ + ㅣ = ㅢ
        XCTAssertEqual(JamoTable.compoundNucleus(first: 18, second: 20), 19)
        // Invalid compound
        XCTAssertNil(JamoTable.compoundNucleus(first: 0, second: 1))
    }

    func testCompoundCodas() {
        // ㄱ + ㅅ = ㄳ
        XCTAssertEqual(JamoTable.compoundCoda(first: 1, second: 19), 3)
        // ㄹ + ㄱ = ㄺ
        XCTAssertEqual(JamoTable.compoundCoda(first: 8, second: 1), 9)
        // ㅂ + ㅅ = ㅄ
        XCTAssertEqual(JamoTable.compoundCoda(first: 17, second: 19), 18)
        // Invalid compound
        XCTAssertNil(JamoTable.compoundCoda(first: 1, second: 1))
    }

    // MARK: - Unicode Composition

    func testComposeSyllable() {
        // 가: onset ㄱ(0), nucleus ㅏ(0), no coda
        XCTAssertEqual(JamoTable.composeSyllable(onset: 0, nucleus: 0), "가")
        // 한: onset ㅎ(18), nucleus ㅏ(0), coda ㄴ(4)
        XCTAssertEqual(JamoTable.composeSyllable(onset: 18, nucleus: 0, coda: 4), "한")
        // 글: onset ㄱ(0), nucleus ㅡ(18), coda ㄹ(8)
        XCTAssertEqual(JamoTable.composeSyllable(onset: 0, nucleus: 18, coda: 8), "글")
    }
}
