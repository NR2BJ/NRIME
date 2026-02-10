import XCTest
@testable import NRIME

final class RomajiComposerTests: XCTestCase {

    private var composer: RomajiComposer!

    override func setUp() {
        super.setUp()
        composer = RomajiComposer()
    }

    // MARK: - Helper

    /// Type a string and return (composedKana, pendingRomaji).
    private func type(_ text: String) -> (kana: String, pending: String) {
        var result = RomajiResult(composing: "", pending: "", committed: "")
        for char in text {
            result = composer.input(char)
        }
        return (result.composing, result.pending)
    }

    // MARK: - Basic Vowels

    func testVowels() {
        let r = type("a")
        XCTAssertEqual(r.kana, "あ")
        XCTAssertEqual(r.pending, "")
    }

    func testAllVowels() {
        let r = type("aiueo")
        XCTAssertEqual(r.kana, "あいうえお")
        XCTAssertEqual(r.pending, "")
    }

    // MARK: - Consonant + Vowel

    func testKa() {
        let r = type("ka")
        XCTAssertEqual(r.kana, "か")
        XCTAssertEqual(r.pending, "")
    }

    func testShi() {
        let r = type("shi")
        XCTAssertEqual(r.kana, "し")
    }

    func testSi() {
        let r = type("si")
        XCTAssertEqual(r.kana, "し")
    }

    func testChi() {
        let r = type("chi")
        XCTAssertEqual(r.kana, "ち")
    }

    func testTsu() {
        let r = type("tsu")
        XCTAssertEqual(r.kana, "つ")
    }

    func testFu() {
        let r = type("fu")
        XCTAssertEqual(r.kana, "ふ")
    }

    // MARK: - N handling

    func testNn() {
        // "nn" → ん immediately
        let r = type("nn")
        XCTAssertEqual(r.kana, "ん")
        XCTAssertEqual(r.pending, "")
    }

    func testNBeforeConsonant() {
        // "n" + consonant (not n/y) → ん + consonant pending
        let r = type("nk")
        XCTAssertEqual(r.kana, "ん")
        XCTAssertEqual(r.pending, "k")
    }

    func testNBeforeVowel() {
        // "na" → な (not ん + あ)
        let r = type("na")
        XCTAssertEqual(r.kana, "な")
    }

    func testNna() {
        // "nn" → ん immediately, then "a" → あ
        let r = type("nna")
        XCTAssertEqual(r.kana, "んあ")
    }

    func testNya() {
        // "nya" → にゃ
        let r = type("nya")
        XCTAssertEqual(r.kana, "にゃ")
    }

    func testNFlush() {
        // Lone "n" at flush → ん
        _ = type("n")
        let result = composer.flush()
        XCTAssertEqual(result, "ん")
    }

    // MARK: - Sokuon (っ)

    func testSokuonKka() {
        let r = type("kka")
        XCTAssertEqual(r.kana, "っか")
    }

    func testSokuonTta() {
        let r = type("tta")
        XCTAssertEqual(r.kana, "った")
    }

    func testSokuonPpa() {
        let r = type("ppa")
        XCTAssertEqual(r.kana, "っぱ")
    }

    func testSokuonSshi() {
        let r = type("sshi")
        XCTAssertEqual(r.kana, "っし")
    }

    // MARK: - Youon (contracted sounds)

    func testKyo() {
        let r = type("kyo")
        XCTAssertEqual(r.kana, "きょ")
    }

    func testSha() {
        let r = type("sha")
        XCTAssertEqual(r.kana, "しゃ")
    }

    func testCha() {
        let r = type("cha")
        XCTAssertEqual(r.kana, "ちゃ")
    }

    func testJa() {
        let r = type("ja")
        XCTAssertEqual(r.kana, "じゃ")
    }

    // MARK: - Words

    func testTokyo() {
        // toukyou → とうきょう
        let r = type("toukyou")
        XCTAssertEqual(r.kana, "とうきょう")
    }

    func testKonnichiwa() {
        // ko→こ, nn→ん, i→い, chi→ち, wa→わ
        // (こんにちわ requires "konnnichiwa" with triple-n, or "konnitiwa")
        let r = type("konnichiwa")
        XCTAssertEqual(r.kana, "こんいちわ")
    }

    func testSakura() {
        let r = type("sakura")
        XCTAssertEqual(r.kana, "さくら")
    }

    func testGakkou() {
        // gakkou → がっこう
        let r = type("gakkou")
        XCTAssertEqual(r.kana, "がっこう")
    }

    func testSensei() {
        let r = type("sensei")
        XCTAssertEqual(r.kana, "せんせい")
    }

    func testNihongo() {
        let r = type("nihongo")
        XCTAssertEqual(r.kana, "にほんご")
    }

    // MARK: - Dakuten (voiced)

    func testGa() {
        let r = type("ga")
        XCTAssertEqual(r.kana, "が")
    }

    func testZa() {
        let r = type("za")
        XCTAssertEqual(r.kana, "ざ")
    }

    func testDa() {
        let r = type("da")
        XCTAssertEqual(r.kana, "だ")
    }

    func testBa() {
        let r = type("ba")
        XCTAssertEqual(r.kana, "ば")
    }

    // MARK: - Handakuten

    func testPa() {
        let r = type("pa")
        XCTAssertEqual(r.kana, "ぱ")
    }

    // MARK: - Small kana

    func testXtu() {
        let r = type("xtu")
        XCTAssertEqual(r.kana, "っ")
    }

    func testXa() {
        let r = type("xa")
        XCTAssertEqual(r.kana, "ぁ")
    }

    // MARK: - Punctuation

    func testLongVowelMark() {
        let r = type("-")
        XCTAssertEqual(r.kana, "ー")
    }

    // MARK: - Backspace

    func testBackspacePending() {
        // Type "k" (pending), then backspace → empty
        _ = type("k")
        let r = composer.deleteBackward()
        XCTAssertEqual(r.composing, "")
        XCTAssertEqual(r.pending, "")
    }

    func testBackspaceComposed() {
        // Type "ka" → か, then backspace → empty
        _ = type("ka")
        let r = composer.deleteBackward()
        XCTAssertEqual(r.composing, "")
        XCTAssertEqual(r.pending, "")
    }

    func testBackspaceMultipleKana() {
        // Type "kaki" → かき, backspace → か
        _ = type("kaki")
        let r = composer.deleteBackward()
        XCTAssertEqual(r.composing, "か")
        XCTAssertEqual(r.pending, "")
    }

    // MARK: - Clear

    func testClear() {
        _ = type("kaki")
        composer.clear()
        XCTAssertFalse(composer.isComposing)
        XCTAssertEqual(composer.composedKana, "")
        XCTAssertEqual(composer.pendingRomaji, "")
    }

    // MARK: - Pending state

    func testPendingK() {
        let r = type("k")
        XCTAssertEqual(r.kana, "")
        XCTAssertEqual(r.pending, "k")
    }

    func testPendingSh() {
        let r = type("sh")
        XCTAssertEqual(r.kana, "")
        XCTAssertEqual(r.pending, "sh")
    }

    func testPendingCh() {
        let r = type("ch")
        XCTAssertEqual(r.kana, "")
        XCTAssertEqual(r.pending, "ch")
    }

    // MARK: - isComposing

    func testIsComposingFalseWhenEmpty() {
        XCTAssertFalse(composer.isComposing)
    }

    func testIsComposingTrueWithPending() {
        _ = type("k")
        XCTAssertTrue(composer.isComposing)
    }

    func testIsComposingTrueWithKana() {
        _ = type("ka")
        XCTAssertTrue(composer.isComposing)
    }
}
