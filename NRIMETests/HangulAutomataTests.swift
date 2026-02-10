import XCTest
@testable import NRIME

final class HangulAutomataTests: XCTestCase {

    private var automata: HangulAutomata!

    override func setUp() {
        super.setUp()
        automata = HangulAutomata()
    }

    // MARK: - Helper

    /// Simulate typing a sequence of QWERTY characters and return the final committed + composing text.
    private func type(_ characters: String) -> (committed: String, composing: String) {
        var committed = ""
        for char in characters {
            guard let jamo = JamoTable.jamo(for: char) else {
                // Non-jamo character: flush and append
                committed += automata.flush()
                committed += String(char)
                continue
            }
            let result = automata.input(jamo)
            committed += result.committed
        }
        return (committed, automata.currentComposingText())
    }

    // MARK: - Basic Consonant/Vowel

    func testSingleConsonant() {
        let result = type("r")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "ㄱ")
    }

    func testConsecutiveConsonants() {
        let result = type("rs")
        XCTAssertEqual(result.committed, "ㄱ")
        XCTAssertEqual(result.composing, "ㄴ")
    }

    func testOnsetAndNucleus() {
        // r=ㄱ, k=ㅏ → 가
        let result = type("rk")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "가")
    }

    // MARK: - Full Syllable Composition

    func testOnsetNucleusCoda() {
        // r=ㄱ, k=ㅏ, t=ㅅ → 갓
        let result = type("rkt")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "갓")
    }

    func testCodaSplitOnVowel() {
        // r=ㄱ, k=ㅏ, t=ㅅ(종성), k=ㅏ → 가 + 사(composing)
        // 갓 + ㅏ → commit 가, new syllable ㅅ+ㅏ = 사
        let result = type("rktk")
        XCTAssertEqual(result.committed, "가")
        XCTAssertEqual(result.composing, "사")
    }

    // MARK: - Compound Vowels

    func testCompoundVowel_ㅘ() {
        // d=ㅇ, h=ㅗ, k=ㅏ → 와 (ㅇ + ㅘ)
        let result = type("dhk")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "와")
    }

    func testCompoundVowel_ㅝ() {
        // d=ㅇ, n=ㅜ, j=ㅓ → 워 (ㅇ + ㅝ)
        let result = type("dnj")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "워")
    }

    func testCompoundVowel_ㅢ() {
        // d=ㅇ, m=ㅡ, l=ㅣ → 의 (ㅇ + ㅢ)
        let result = type("dml")
        XCTAssertEqual(result.committed, "")
        XCTAssertEqual(result.composing, "의")
    }

    // MARK: - Compound Codas

    func testCompoundCoda_ㄳ() {
        // r=ㄱ, k=ㅏ, r=ㄱ(종성), t=ㅅ → 갃(ㄱ+ㅏ+ㄳ)
        // onset=0(ㄱ), nucleus=0(ㅏ), coda: ㄱ(1)+ㅅ(19)=ㄳ(3)
        let result = type("rkrt")
        XCTAssertEqual(result.committed, "")
        // ㄱ(onset 0) + ㅏ(nucleus 0) + ㄳ(coda 3) = 0*21*28 + 0*28 + 3 + 0xAC00 = 0xAC03
        let expected = String(Unicode.Scalar(0xAC03)!)
        XCTAssertEqual(result.composing, expected)
    }

    func testCompoundCodaSplitOnVowel() {
        // r=ㄱ, k=ㅏ, r=ㄱ(종성), t=ㅅ(compound종성ㄳ), k=ㅏ
        // → commit "갃" without second coda (갂→ no, keep ㄱ as coda: 각), new syllable ㅅ+ㅏ = 사
        // Actually: compound coda ㄳ splits → keep ㄱ(first=1) as coda, ㅅ(second=19) becomes onset
        // Committed: ㄱ+ㅏ+ㄱ(coda 1) = 각 (0*21*28 + 0*28 + 1 + 0xAC00 = 0xAC01)
        let result = type("rkrtk")
        let gak = String(Unicode.Scalar(0xAC01)!) // 각
        XCTAssertEqual(result.committed, gak)
        XCTAssertEqual(result.composing, "사")
    }

    // MARK: - Double Consonants Cannot Be Coda

    func testDoubleConsonantCannotBeCoda() {
        // r=ㄱ, k=ㅏ → 가, then E=ㄸ (cannot be coda) → commit 가, composing ㄸ
        let result = type("rkE")
        XCTAssertEqual(result.committed, "가")
        XCTAssertEqual(result.composing, "ㄸ")
    }

    // MARK: - Backspace

    func testBackspaceFromOnsetNucleus() {
        // r=ㄱ, k=ㅏ → 가, then backspace → ㄱ
        let _ = type("rk")
        let result = automata.deleteBackward()
        XCTAssertEqual(result.composing, "ㄱ")
    }

    func testBackspaceFromOnsetNucleusCoda() {
        // r=ㄱ, k=ㅏ, t=ㅅ → 갓, then backspace → 가
        let _ = type("rkt")
        let result = automata.deleteBackward()
        XCTAssertEqual(result.composing, "가")
    }

    func testBackspaceFromCompoundCoda() {
        // r=ㄱ, k=ㅏ, r=ㄱ, t=ㅅ → compound coda ㄳ, backspace → 각
        let _ = type("rkrt")
        let result = automata.deleteBackward()
        let gak = String(Unicode.Scalar(0xAC01)!) // 각
        XCTAssertEqual(result.composing, gak)
    }

    func testBackspaceFromCompoundVowel() {
        // d=ㅇ, h=ㅗ, k=ㅏ → 와 (compound ㅘ), backspace → 오
        let _ = type("dhk")
        let result = automata.deleteBackward()
        XCTAssertEqual(result.composing, "오")
    }

    func testBackspaceFromOnset() {
        let _ = type("r")
        let result = automata.deleteBackward()
        XCTAssertEqual(result.composing, "")
    }

    func testBackspaceFromEmpty() {
        let result = automata.deleteBackward()
        XCTAssertEqual(result.composing, "")
        XCTAssertEqual(result.committed, "")
    }

    // MARK: - Flush

    func testFlush() {
        let _ = type("rk")
        let flushed = automata.flush()
        XCTAssertEqual(flushed, "가")
        XCTAssertFalse(automata.isComposing)
    }

    // MARK: - Real Word Tests

    func testTyping_한글() {
        // 한: g=ㅎ, k=ㅏ, s=ㄴ → 한
        // 글: r=ㄱ, m=ㅡ, f=ㄹ → 글
        // gks → 한 (ㅎ+ㅏ+ㄴ), then r(ㄱ) → 한 splits? No, ㄱ is consonant after 한(종성 ㄴ).
        // ㄴ+ㄱ: check compound coda → ㄴ(4) + ㄱ(1) → no compound. So commit 한, new onset ㄱ
        // Then m=ㅡ → 그, f=ㄹ → 글
        let result = type("gksrmf")
        XCTAssertEqual(result.committed, "한")
        XCTAssertEqual(result.composing, "글")
    }

    func testTyping_대한민국() {
        // 대한민국 = eogksalsrnr
        // e=ㄷ, o=ㅐ → 대(composing)
        // g=ㅎ → 대 has onset+nucleus, ㅎ can be coda(27) → 댛(composing)
        // k=ㅏ → split: remove ㅎ, commit 대, new ㅎ+ㅏ = 하(composing)
        // s=ㄴ → 한(coda ㄴ=4, composing)
        // a=ㅁ → no compound(ㄴ+ㅁ), commit 한, onset ㅁ
        // l=ㅣ → 미
        // s=ㄴ → 민(coda)
        // r=ㄱ → no compound(ㄴ+ㄱ), commit 민, onset ㄱ
        // n=ㅜ → 구
        // r=ㄱ → 국(coda)
        let result = type("eogksalsrnr")
        XCTAssertEqual(result.committed, "대한민")
        XCTAssertEqual(result.composing, "국")
    }

    func testTyping_둘_다() {
        // "둘 다" = enf + space + ek
        // e=ㄷ, n=ㅜ, f=ㄹ → 둘(composing)
        // space → non-jamo, flush "둘", committed="둘 "
        // e=ㄷ → onset(composing=ㄷ)
        // k=ㅏ → composing=다
        let result = type("enf ek")
        XCTAssertEqual(result.committed, "둘 ")
        XCTAssertEqual(result.composing, "다")
    }

    func testTyping_뛰어() {
        // "뛰어" = Enl + dj
        // E=ㄸ → onset
        // n=ㅜ → 뚜(onsetNucleus)
        // l=ㅣ → 뛔? no... ㅜ(13)+ㅣ(20) = ㅟ(16) compound → 뛰(composing)
        // d=ㅇ → ㅇ can be coda(21) → 뛱(composing)
        // j=ㅓ → split: commit 뛰, new ㅇ+ㅓ = 어(composing)
        let result = type("Enldj")
        XCTAssertEqual(result.committed, "뛰")
        XCTAssertEqual(result.composing, "어")
    }

    func testTyping_사랑() {
        // 사: t=ㅅ, k=ㅏ → 사
        // 랑: f=ㄹ, k=ㅏ... wait
        // 사: t=ㅅ, k=ㅏ → 사(composing)
        // f=ㄹ → 살(coda)... ㄹ can be coda(8)
        // k=ㅏ → split: commit 사, new onset ㄹ+ㅏ = 라
        // d=ㅇ → 란(coda? no, ㅇ coda index = 21) → 랑... wait
        // Actually for "사랑" we need: tkfkd
        // t=ㅅ → ㅅ
        // k=ㅏ → 사
        // f=ㄹ → 살(coda ㄹ=8)
        // k=ㅏ → split: commit 사, new ㄹ+ㅏ = 라
        // d=ㅇ → 랑(coda ㅇ=21)
        let result = type("tkfkd")
        XCTAssertEqual(result.committed, "사")
        XCTAssertEqual(result.composing, "랑")
    }
}
