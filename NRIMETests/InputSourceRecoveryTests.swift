import XCTest
@testable import NRIME

final class InputSourceRecoveryTests: XCTestCase {

    func testDoesNotRecoverWhenPreventABCSwitchIsDisabled() {
        XCTAssertFalse(InputSourceRecovery.shouldRecoverInputSource(
            preventABCSwitch: false,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: true,
            secureInputActive: false
        ))
    }

    func testUserInitiatedSwitchSuppressesRecovery() {
        XCTAssertFalse(InputSourceRecovery.shouldRecoverInputSource(
            preventABCSwitch: true,
            userInitiatedSwitch: true,
            currentSourceIsNonNRIME: true,
            secureInputActive: false
        ))
    }

    func testSecureInputSuppressesRecovery() {
        XCTAssertFalse(InputSourceRecovery.shouldRecoverInputSource(
            preventABCSwitch: true,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: true,
            secureInputActive: true
        ))
    }

    func testCurrentNRIMESourceDoesNotRecover() {
        XCTAssertFalse(InputSourceRecovery.shouldRecoverInputSource(
            preventABCSwitch: true,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: false,
            secureInputActive: false
        ))
    }

    func testNonNRIMESourceRecoversWhenProtectionIsEnabled() {
        XCTAssertTrue(InputSourceRecovery.shouldRecoverInputSource(
            preventABCSwitch: true,
            userInitiatedSwitch: false,
            currentSourceIsNonNRIME: true,
            secureInputActive: false
        ))
    }

    func testRecoveryThrottleUpdatesStateAtomicallyWithinWindow() {
        let now = Date()
        let state = InputSourceRecovery.RecoveryThrottleState(
            consecutiveRecoveries: 1,
            lastRecoveryTime: now.addingTimeInterval(-1)
        )

        let decision = InputSourceRecovery.evaluateRecoveryThrottle(
            now: now,
            state: state,
            maxConsecutiveRecoveries: 3
        )

        guard case let .recover(nextState) = decision else {
            return XCTFail("Expected recovery to proceed")
        }
        XCTAssertEqual(nextState.consecutiveRecoveries, 2)
        XCTAssertEqual(nextState.lastRecoveryTime, now)
    }

    func testRecoveryThrottleResetsCountAfterWindowExpires() {
        let now = Date()
        let state = InputSourceRecovery.RecoveryThrottleState(
            consecutiveRecoveries: 2,
            lastRecoveryTime: now.addingTimeInterval(-3)
        )

        let decision = InputSourceRecovery.evaluateRecoveryThrottle(
            now: now,
            state: state,
            maxConsecutiveRecoveries: 3
        )

        guard case let .recover(nextState) = decision else {
            return XCTFail("Expected recovery to proceed")
        }
        XCTAssertEqual(nextState.consecutiveRecoveries, 0)
        XCTAssertEqual(nextState.lastRecoveryTime, now)
    }

    func testRecoveryThrottleHaltsAtConfiguredLimit() {
        let now = Date()
        let priorTime = now.addingTimeInterval(-1)
        let state = InputSourceRecovery.RecoveryThrottleState(
            consecutiveRecoveries: 2,
            lastRecoveryTime: priorTime
        )

        let decision = InputSourceRecovery.evaluateRecoveryThrottle(
            now: now,
            state: state,
            maxConsecutiveRecoveries: 3
        )

        guard case let .halt(nextState) = decision else {
            return XCTFail("Expected recovery to halt")
        }
        XCTAssertEqual(nextState.consecutiveRecoveries, 3)
        XCTAssertEqual(nextState.lastRecoveryTime, priorTime)
    }
}
