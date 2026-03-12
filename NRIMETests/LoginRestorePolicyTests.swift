import XCTest
@testable import NRIME

final class LoginRestorePolicyTests: XCTestCase {

    func testAttemptDelaysStartImmediatelyAndFinishAtStabilizationBoundary() {
        let delays = LoginRestorePolicy.attemptDelays()

        XCTAssertEqual(delays.first, 0)
        XCTAssertEqual(delays.last, LoginRestorePolicy.stabilizationDuration)
    }

    func testAttemptDelaysStaySortedAndBounded() {
        let delays = LoginRestorePolicy.attemptDelays()

        XCTAssertEqual(delays, delays.sorted())
        XCTAssertTrue(delays.allSatisfy { $0 >= 0 && $0 <= LoginRestorePolicy.stabilizationDuration })
    }

    func testAttemptDelaysUseConfiguredPollIntervalWithoutLargeGaps() {
        let delays = LoginRestorePolicy.attemptDelays()

        for pair in zip(delays, delays.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.1 - pair.0, LoginRestorePolicy.pollInterval + 0.0001)
        }
    }
}
