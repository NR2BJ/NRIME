import CoreGraphics
import XCTest
@testable import NRIME

final class OverlayWindowLevelTests: XCTestCase {
    func testUsesFloatingLevelWhenFrontmostAppHasNoHighLayer() {
        XCTAssertEqual(
            OverlayWindowLevel.overlayLevelRawValue(
                frontmostWindowLayers: [0],
                base: 3,
                maximum: 999
            ),
            3
        )
    }

    func testRisesAboveFrontmostHighLayer() {
        XCTAssertEqual(
            OverlayWindowLevel.overlayLevelRawValue(
                frontmostWindowLayers: [0, 101],
                base: 3,
                maximum: 999
            ),
            102
        )
    }

    func testKnownHighPriorityAppGetsPopupMenuFallbackLevel() {
        XCTAssertEqual(
            OverlayWindowLevel.overlayLevelRawValue(
                frontmostWindowLayers: [0],
                frontmostBundleID: "com.apple.Spotlight",
                base: 3,
                maximum: 999
            ),
            Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1
        )
    }

    func testCapsBelowScreenSaverLevel() {
        XCTAssertEqual(
            OverlayWindowLevel.overlayLevelRawValue(
                frontmostWindowLayers: [1200],
                base: 3,
                maximum: 999
            ),
            999
        )
    }
}
