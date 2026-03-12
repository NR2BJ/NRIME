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
}
