import XCTest
@testable import NRIME

final class TextInputGeometryTests: XCTestCase {

    func testCaretRectUsesSelectedRangeForFirstRectLookup() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 12, length: 0))
        client.firstRectResponse = NSRect(x: 320, y: 240, width: 14, height: 20)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, client.firstRectResponse)
        XCTAssertEqual(client.lastFirstRectRange, NSRange(location: 12, length: 0))
        XCTAssertNil(client.lastAttributesCharacterIndex)
    }

    func testCaretRectPrefersMarkedRangeOverSelectedRange() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 0, length: 0))
        client.setMarkedText("かな", selectionRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        client.firstRectResponse = NSRect(x: 840, y: 520, width: 14, height: 20)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, client.firstRectResponse)
        XCTAssertEqual(client.lastFirstRectRange, NSRange(location: 2, length: 0))
    }

    func testCaretRectPrefersSelectedRangeWhenItMatchesMarkedTextCaret() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 9, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 8, length: 3))
        client.firstRectResponse = NSRect(x: 500, y: 420, width: 12, height: 18)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, client.firstRectResponse)
        XCTAssertEqual(client.lastFirstRectRange, NSRange(location: 9, length: 0))
    }

    func testCaretIndexFallsBackToMarkedRangeEnd() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: NSNotFound, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 3))

        let index = TextInputGeometry.caretIndex(for: client)

        XCTAssertEqual(index, 7)
    }

    func testCaretIndexPrefersMarkedRangeOverSelectedRange() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 0, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 3))

        let index = TextInputGeometry.caretIndex(for: client)

        XCTAssertEqual(index, 7)
    }

    func testCaretRectFallsBackToAttributesOnlyWhenUsable() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: NSNotFound, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 3, length: 2))
        client.firstRectResponse = .zero
        client.attributesRectResponse = NSRect(x: 420, y: 260, width: 12, height: 18)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, client.attributesRectResponse)
        XCTAssertEqual(client.lastAttributesCharacterIndex, 5)
    }

    func testCaretRectRejectsOriginRectThatWouldPinPanelToScreenCorner() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 0, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        client.firstRectResponse = NSRect(x: 0, y: 0, width: 12, height: 18)
        client.attributesRectResponse = NSRect(x: 0, y: 0, width: 12, height: 18)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertNil(rect)
    }

    func testCaretRectUsesFirstRectWhenExpandedMarkedSpanIsUsable() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 9, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 8, length: 3))
        client.firstRectResponse = NSRect(x: 420, y: 260, width: 88, height: 18)
        client.firstRectActualRangeResponse = NSRange(location: 8, length: 3)
        client.attributesRectResponse = NSRect(x: 486, y: 260, width: 12, height: 18)

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, client.firstRectResponse)
        XCTAssertNil(client.lastAttributesCharacterIndex)
    }

    func testCaretRectSkipsSuspiciousWideZeroLengthRectInFavorOfSingleCharacterRect() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 12, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 10, length: 3))
        client.setFirstRectResponse(
            NSRect(x: 24, y: 320, width: 680, height: 20),
            actualRange: NSRange(location: 0, length: 1),
            for: NSRange(location: 12, length: 0)
        )
        client.setFirstRectResponse(
            NSRect(x: 216, y: 320, width: 14, height: 20),
            actualRange: NSRange(location: 12, length: 1),
            for: NSRange(location: 12, length: 1)
        )

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(rect, NSRect(x: 216, y: 320, width: 14, height: 20))
        XCTAssertEqual(client.lastFirstRectRange, NSRange(location: 12, length: 1))
    }

    func testCaretRectFallsBackToAttributesIndex0WhenAllElseFails() {
        // Simulates Electron apps: firstRect returns wide rect, attributes(caretIndex) returns zero.
        // Should fall back to attributes(0) like Squirrel/AquaSKK do.
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 5, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        // All firstRect calls return a suspiciously wide rect (entire input field)
        client.firstRectResponse = NSRect(x: 100, y: 300, width: 800, height: 20)
        // attributes returns zero for caretIndex but usable for index 0
        client.attributesRectResponse = NSRect(x: 100, y: 300, width: 12, height: 20)

        let rect = TextInputGeometry.caretRect(for: client)

        // Should get attributes rect (at whichever index succeeds)
        XCTAssertNotNil(rect)
        XCTAssertEqual(rect?.origin.y, 300)
        XCTAssertEqual(rect?.height, 20)
    }

    func testCaretRectReturnsNilWhenAllSourcesFail() {
        // All sources return unusable data
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 5, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        client.firstRectResponse = NSRect(x: 100, y: 300, width: 800, height: 20)
        client.attributesRectResponse = .zero

        let rect = TextInputGeometry.caretRect(for: client)

        XCTAssertNil(rect)
    }

    func testCaretRectPrefersAttributesOverSuspiciousRect() {
        // When firstRect returns suspicious wide rects but attributes returns a good rect
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 5, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        client.firstRectResponse = NSRect(x: 100, y: 300, width: 800, height: 20)
        // attributes returns a good, usable rect
        client.attributesRectResponse = NSRect(x: 420, y: 300, width: 12, height: 20)

        let rect = TextInputGeometry.caretRect(for: client)

        // Should prefer attributes rect over the suspicious wide rect
        XCTAssertEqual(rect, NSRect(x: 420, y: 300, width: 12, height: 20))
    }

    func testBestScreenFramePrefersScreenContainingCaretRect() {
        let primary = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let secondary = NSRect(x: 1728, y: 0, width: 1728, height: 1117)
        let caretRect = NSRect(x: 2400, y: 480, width: 12, height: 20)

        let screenFrame = TextInputGeometry.bestScreenFrame(for: caretRect, screenFrames: [primary, secondary])

        XCTAssertEqual(screenFrame, secondary)
    }

    func testBestScreenFrameFallsBackToNearestScreenWhenRectMissesAllFrames() {
        let left = NSRect(x: -1512, y: 0, width: 1512, height: 982)
        let center = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let offscreenRect = NSRect(x: -40, y: 400, width: 20, height: 20)

        let screenFrame = TextInputGeometry.bestScreenFrame(for: offscreenRect, screenFrames: [left, center])

        XCTAssertEqual(screenFrame, left)
    }

    func testPanelOriginXPrefersOpeningToTheRightWhenSpaceIsAvailable() {
        let anchorRect = NSRect(x: 320, y: 200, width: 12, height: 18)
        let screenFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)

        let x = TextInputGeometry.panelOriginX(for: anchorRect, panelWidth: 240, within: screenFrame)

        XCTAssertEqual(x, 334)
    }

    func testPanelOriginXOpensLeftwardWhenRightSpaceRunsOut() {
        let anchorRect = NSRect(x: 1110, y: 200, width: 12, height: 18)
        let screenFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)

        let x = TextInputGeometry.panelOriginX(for: anchorRect, panelWidth: 240, within: screenFrame)

        XCTAssertEqual(x, 868)
    }

}
