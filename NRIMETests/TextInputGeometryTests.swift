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

    func testCaretIndexFallsBackToMarkedRangeEnd() {
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: NSNotFound, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 3))

        let index = TextInputGeometry.caretIndex(for: client)

        XCTAssertEqual(index, 7)
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
}
