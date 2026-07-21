import XCTest
@testable import NRIME

final class JapaneseEngineTests: XCTestCase {

    private var engine: JapaneseEngine!
    private var client: MockTextInputClient!
    private var originalConfig: JapaneseKeyConfig!

    override func setUp() {
        super.setUp()
        // Pin a known config so tests don't depend on (or pollute) real user settings.
        originalConfig = Settings.shared.japaneseKeyConfig
        var config = JapaneseKeyConfig.default
        config.prediction = false      // no Mozc IPC in unit tests
        config.liveConversion = false
        Settings.shared.japaneseKeyConfig = config
        engine = JapaneseEngine()
        client = MockTextInputClient()
    }

    override func tearDown() {
        Settings.shared.japaneseKeyConfig = originalConfig
        engine = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Commit pattern (Firefox/Papago: no setMarkedText("") around insertText)

    func testEnterCommitUsesInsertTextOnly() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x00), client: client)) // a → あ
        XCTAssertEqual(client.markedString, "あ")

        let handled = engine.handleEvent(keyEvent(keyCode: 0x24), client: client) // Enter

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["あ"])
        XCTAssertEqual(client.composedText, "あ")
        XCTAssertEqual(client.markedString, "")
        // The commit must not emit setMarkedText("") — Chromium/JS-managed editors
        // (Papago etc.) delete the inserted text when composition is cleared first.
        XCTAssertEqual(client.markedTextHistory, ["あ"])
    }

    func testForceCommitUsesInsertTextOnly() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x00), client: client)) // a → か

        engine.forceCommit(client: client)

        XCTAssertEqual(client.insertedTexts, ["か"])
        XCTAssertFalse(client.markedTextHistory.contains(""))
    }

    // MARK: - Styled symbols (engine flow)

    func testPeriodCommitsComposingAndInsertsStyledSymbol() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x00), client: client)) // a → か

        let handled = engine.handleEvent(keyEvent(keyCode: 0x2F), client: client) // .

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["か", "。"])
        XCTAssertEqual(client.composedText, "か。")
        XCTAssertFalse(client.markedTextHistory.contains(""))
    }

    func testShiftedQuestionMarkFollowsPunctuationStyle() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x00), client: client)) // a → あ

        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x2C, modifiers: [.shift]), client: client) // Shift+/ = ?

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["あ", "？"])
        XCTAssertEqual(client.composedText, "あ？")
    }

    func testShiftedSymbolPassesThroughInRomajiShiftMode() {
        var config = Settings.shared.japaneseKeyConfig
        config.shiftKeyAction = .romaji
        Settings.shared.japaneseKeyConfig = config

        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x12, modifiers: [.shift]), client: client) // Shift+1 = !

        XCTAssertFalse(handled, "Shift-romaji mode should pass raw ASCII through")
        XCTAssertEqual(client.insertedTexts, [])
    }

    // MARK: - Styled symbol mapping (pure)

    func testStyledSymbolJapaneseStyle() {
        let config = JapaneseKeyConfig.default // .japanese, nakaguro on

        XCTAssertEqual(symbol(0x12, shifted: true, config), "！")
        XCTAssertEqual(symbol(0x2C, shifted: true, config), "？")
        XCTAssertEqual(symbol(0x19, shifted: true, config), "（")
        XCTAssertEqual(symbol(0x1D, shifted: true, config), "）")
        XCTAssertEqual(symbol(0x21, shifted: false, config), "「")
        XCTAssertEqual(symbol(0x1E, shifted: false, config), "」")
        XCTAssertEqual(symbol(0x32, shifted: true, config), "\u{301C}") // 〜 wave dash
        XCTAssertEqual(symbol(0x29, shifted: false, config), "；")
        XCTAssertEqual(symbol(0x29, shifted: true, config), "：")
        XCTAssertEqual(symbol(0x2C, shifted: false, config), "・")     // nakaguro on
    }

    func testStyledSymbolFullWidthWesternStyle() {
        var config = JapaneseKeyConfig.default
        config.punctuationStyle = .fullWidthWestern

        XCTAssertEqual(symbol(0x2F, shifted: false, config), "．")
        XCTAssertEqual(symbol(0x12, shifted: true, config), "！")
        XCTAssertEqual(symbol(0x21, shifted: false, config), "［")
        XCTAssertEqual(symbol(0x1E, shifted: false, config), "］")
        XCTAssertEqual(symbol(0x32, shifted: true, config), "\u{FF5E}") // ～ full-width tilde
    }

    func testStyledSymbolHalfWidthWesternStyleStaysASCII() {
        var config = JapaneseKeyConfig.default
        config.punctuationStyle = .halfWidthWestern

        XCTAssertEqual(symbol(0x2F, shifted: false, config), ".")
        XCTAssertEqual(symbol(0x12, shifted: true, config), "!")
        XCTAssertEqual(symbol(0x2C, shifted: true, config), "?")
        XCTAssertEqual(symbol(0x21, shifted: false, config), "[")
        XCTAssertEqual(symbol(0x29, shifted: false, config), ";")
        XCTAssertEqual(symbol(0x32, shifted: true, config), "~")
    }

    func testStyledSymbolLeavesComposerKeysAlone() {
        let config = JapaneseKeyConfig.default

        // Unshifted "-" is the long-vowel mark ー, handled by RomajiComposer
        XCTAssertNil(symbol(0x1B, shifted: false, config))
        // Alphabet and unshifted numbers are not symbols
        XCTAssertNil(symbol(0x00, shifted: false, config)) // a
        XCTAssertNil(symbol(0x12, shifted: false, config)) // 1
    }

    func testSlashFollowsWidthStyleWhenNakaguroOff() {
        var config = JapaneseKeyConfig.default
        config.slashToNakaguro = false

        XCTAssertEqual(symbol(0x2C, shifted: false, config), "\u{FF0F}") // ／

        config.punctuationStyle = .halfWidthWestern
        XCTAssertEqual(symbol(0x2C, shifted: false, config), "/")
    }

    private func symbol(_ keyCode: UInt16, shifted: Bool, _ config: JapaneseKeyConfig) -> String? {
        JapaneseEngine.styledSymbol(keyCode: keyCode, shifted: shifted, config: config)
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create NSEvent")
            fatalError("Failed to create NSEvent")
        }
        return event
    }

    func testConversionFallbackPrefersCurrentPreedit() {
        let preedit = makePreedit(["変", "換"])

        let text = JapaneseEngine.conversionFallbackText(
            preedit: preedit,
            originalHiragana: "へんかん"
        )

        XCTAssertEqual(text, "変換")
    }

    func testConversionFallbackUsesOriginalHiraganaWhenPreeditMissing() {
        let text = JapaneseEngine.conversionFallbackText(
            preedit: nil,
            originalHiragana: "かな"
        )

        XCTAssertEqual(text, "かな")
    }

    func testLiveConversionCommitTextAppendsResolvedPendingTail() {
        let text = JapaneseEngine.liveConversionCommitText(
            convertedText: "漢字",
            composedKana: "かんじ",
            flushedText: "かんじん"
        )

        XCTAssertEqual(text, "漢字ん")
    }

    private func makePreedit(_ segments: [String]) -> Mozc_Commands_Preedit {
        var preedit = Mozc_Commands_Preedit()
        preedit.segment = segments.map { value in
            var segment = Mozc_Commands_Preedit.Segment()
            segment.value = value
            return segment
        }
        return preedit
    }
}
