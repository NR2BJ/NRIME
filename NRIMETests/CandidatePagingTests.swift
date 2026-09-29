import Cocoa
import XCTest
@testable import NRIME

/// Left/Right in the Japanese candidate list: page when there is one segment
/// (matching the hanja list), move between segments when there are several.
final class CandidatePagingTests: XCTestCase {

    private func direction(_ keyCode: UInt16,
                           modifiers: NSEvent.ModifierFlags = [],
                           segments: Int = 1,
                           grid: Bool = false) -> NRIMEInputController.CandidatePageDirection? {
        NRIMEInputController.listModePageDirection(keyCode: keyCode, modifiers: modifiers,
                                                   segmentCount: segments, gridMode: grid)
    }

    func testSingleSegmentLeftRightPage() {
        XCTAssertEqual(direction(0x7B), .previous)
        XCTAssertEqual(direction(0x7C), .next)
    }

    func testSeveralSegmentsKeepMozcSegmentMovement() {
        XCTAssertNil(direction(0x7B, segments: 3))
        XCTAssertNil(direction(0x7C, segments: 2))
    }

    func testShiftStillResizesSegmentsInMozc() {
        XCTAssertNil(direction(0x7C, modifiers: .shift))
    }

    func testOtherModifiersOptOut() {
        XCTAssertNil(direction(0x7C, modifiers: .option))
        XCTAssertNil(direction(0x7C, modifiers: .command))
        XCTAssertNil(direction(0x7C, modifiers: .control))
    }

    func testGridModeHasItsOwnNavigation() {
        XCTAssertNil(direction(0x7C, grid: true))
    }

    func testOtherKeysAreNotPaging() {
        XCTAssertNil(direction(0x7E)) // Up
        XCTAssertNil(direction(0x7D)) // Down
        XCTAssertNil(direction(0x31)) // Space
    }

    func testNoSegmentsMeansNotConverting() {
        XCTAssertNil(direction(0x7C, segments: 0))
    }
}
