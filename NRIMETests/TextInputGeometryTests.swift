import XCTest
@testable import NRIME

final class TextInputGeometryTests: XCTestCase {

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

        let result = TextInputGeometry.caretRect(for: client)

        XCTAssertEqual(result?.rect, client.attributesRectResponse)
        XCTAssertEqual(result?.source, .attributesAtCaret)
        XCTAssertEqual(client.lastAttributesCharacterIndex, 5)
    }

    func testCaretRectFallsBackToAttributesIndex0WhenAllElseFails() {
        // Simulates Electron apps: firstRect returns wide rect, attributes(caretIndex) returns zero.
        // Should fall back to attributes(0) — only Y/height are reliable, not X.
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 5, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        // All firstRect calls return a suspiciously wide rect (entire input field)
        client.firstRectResponse = NSRect(x: 100, y: 300, width: 800, height: 20)
        // attributes returns usable rect
        client.attributesRectResponse = NSRect(x: 100, y: 300, width: 12, height: 20)

        let result = TextInputGeometry.caretRect(for: client)

        // Should get attributes rect with attributesAtCaret or attributesAtZero source
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rect.origin.y, 300)
        XCTAssertEqual(result?.rect.height, 20)
        // X from index 0 is unreliable — source should indicate this
        XCTAssertTrue(result?.source == .attributesAtCaret || result?.source == .attributesAtZero)
    }

    func testCaretRectPrefersAttributesOverSuspiciousRect() {
        // When firstRect returns suspicious wide rects but attributes returns a good rect
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: 5, length: 0))
        client.setMarkedRangeForTesting(NSRange(location: 4, length: 2))
        client.firstRectResponse = NSRect(x: 100, y: 300, width: 800, height: 20)
        // attributes returns a good, usable rect
        client.attributesRectResponse = NSRect(x: 420, y: 300, width: 12, height: 20)

        let result = TextInputGeometry.caretRect(for: client)

        // Should prefer attributes rect over the suspicious wide rect
        XCTAssertEqual(result?.rect, NSRect(x: 420, y: 300, width: 12, height: 20))
        XCTAssertEqual(result?.source, .attributesAtCaret)
    }

    func testCaretRectIndex0FallbackReportsCorrectSource() {
        // Verify that when only index 0 fallback works, source is .attributesAtZero
        let client = MockTextInputClient()
        client.setSelectedRange(NSRange(location: NSNotFound, length: 0))
        // No marked range, no selected range — caretIndex returns nil
        // firstRect returns zero
        client.firstRectResponse = .zero
        // attributes returns usable rect (this will be hit at index 0 fallback)
        client.attributesRectResponse = NSRect(x: 50, y: 400, width: 10, height: 18)

        let result = TextInputGeometry.caretRect(for: client)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.source, .attributesAtZero)
        XCTAssertEqual(result?.rect.origin.y, 400)
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

    // MARK: - Is the caret inside the app?

    /// A caret the app reports outside its own windows is wrong, even on a screen.
    func testCaretOutsideTheAppsWindowsIsRejected() {
        let windows = [NSRect(x: 100, y: 100, width: 800, height: 600)]
        XCTAssertTrue(TextInputGeometry.caretIsInside(NSRect(x: 300, y: 400, width: 2, height: 18), windowFrames: windows))
        XCTAssertFalse(TextInputGeometry.caretIsInside(NSRect(x: 1200, y: 400, width: 2, height: 18), windowFrames: windows),
                       "Another window's text, a stale spot, a screen corner")
        XCTAssertTrue(TextInputGeometry.caretIsInside(NSRect(x: 1200, y: 400, width: 2, height: 18),
                                                      windowFrames: windows + [NSRect(x: 1000, y: 300, width: 400, height: 300)]),
                      "Any of the app's windows counts (a popover, a second window)")
        XCTAssertTrue(TextInputGeometry.caretIsInside(NSRect(x: 5000, y: 5000, width: 2, height: 18), windowFrames: []),
                      "No window to check against rules nothing out")
    }

}
