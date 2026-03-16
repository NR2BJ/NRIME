import XCTest
@testable import NRIME

final class KoreanEngineTests: XCTestCase {

    private var engine: KoreanEngine!
    private var client: MockTextInputClient!

    override func setUp() {
        super.setUp()
        engine = KoreanEngine()
        client = MockTextInputClient()
    }

    func testSpaceCommitsCurrentCompositionAndPassesThrough() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")

        let handled = engine.handleEvent(keyEvent(keyCode: 0x31, characters: " "), client: client) // Space

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedTexts, ["가"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.composedText, "가")
        XCTAssertFalse(engine.isCurrentlyComposing)
    }

    func testRestoreHanjaSourceRestoresOriginalComposingTextAfterPreview() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x05), client: client)) // g
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x01), client: client)) // s
        XCTAssertEqual(client.markedString, "한")

        XCTAssertTrue(engine.triggerHanjaConversion(client: client))

        client.setMarkedText("韓" as NSString,
                             selectionRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        XCTAssertEqual(client.markedString, "韓")

        engine.restoreHanjaSource(client: client)

        XCTAssertEqual(client.markedString, "한")
        XCTAssertEqual(client.markedSelectionRange, NSRange(location: 1, length: 0))
    }

    func testClearHanjaSessionStopsRestoreFromReintroducingOldText() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x05), client: client)) // g
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x01), client: client)) // s
        XCTAssertTrue(engine.triggerHanjaConversion(client: client))

        client.setMarkedText("韓" as NSString,
                             selectionRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        engine.clearHanjaSession()
        engine.restoreHanjaSource(client: client)

        XCTAssertEqual(client.markedString, "韓")
    }

    // MARK: - Shift+Enter Passthrough Tests

    func testShiftEnterWhileComposingConsumedForRepost() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x0F), client: client)) // r → ㄱ
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k → 가
        XCTAssertEqual(client.markedString, "가")

        // Shift+Enter while composing: consumed (return true).
        // Text committed asynchronously; key re-posted via CGEvent.
        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.shift]),
            client: client
        )

        XCTAssertTrue(handled, "Shift+Enter while composing should be consumed for async repost")
        XCTAssertEqual(client.markedString, "")
        XCTAssertFalse(engine.isCurrentlyComposing)
    }

    func testShiftEnterNotComposingPassesThrough() {
        // When not composing, Shift+Enter should pass through (return false).
        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.shift]),
            client: client
        )

        XCTAssertFalse(handled, "Shift+Enter when not composing should pass through")
        XCTAssertEqual(client.insertedTexts, [])
    }

    // MARK: - Cmd+A Passthrough Tests

    func testCmdAWhileComposingConsumedForRepost() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x0F), client: client)) // r → ㄱ
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k → 가
        XCTAssertEqual(client.markedString, "가")

        // Cmd+A while composing: consumed (return true).
        // Text committed asynchronously; Cmd+A re-posted via CGEvent.
        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        XCTAssertTrue(handled, "Cmd+A while composing should be consumed for async repost")
        XCTAssertEqual(client.markedString, "")
        XCTAssertFalse(engine.isCurrentlyComposing)
    }

    func testCmdANotComposingPassesThrough() {
        // When not composing, Cmd+A should pass through directly.
        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        XCTAssertFalse(handled, "Cmd+A when not composing should pass through immediately")
        XCTAssertEqual(client.insertedTexts, [])
    }

    func testCmdCWhileComposingConsumedForRepost() {
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x0F), client: client)) // r → ㄱ
        XCTAssertTrue(engine.handleEvent(keyEvent(keyCode: 0x28), client: client)) // k → 가

        let handled = engine.handleEvent(
            keyEvent(keyCode: 0x08, characters: "c", modifiers: [.command]),
            client: client
        )

        XCTAssertTrue(handled, "Cmd+C while composing should be consumed for async repost")
    }

    // MARK: - Helpers

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
}
