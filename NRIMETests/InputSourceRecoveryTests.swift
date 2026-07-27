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

    func testUserInitiatedSwitchExpiresAfterGracePeriod() {
        let now = Date()

        let resolution = InputSourceRecovery.resolveUserInitiatedSwitch(
            now: now,
            isActive: true,
            expiresAt: now.addingTimeInterval(-0.1)
        )

        XCTAssertFalse(resolution.isActive)
        XCTAssertNil(resolution.expiresAt)
    }

    func testUserInitiatedSwitchStaysActiveBeforeGracePeriodExpires() {
        let now = Date()
        let expiry = now.addingTimeInterval(4.0)

        let resolution = InputSourceRecovery.resolveUserInitiatedSwitch(
            now: now,
            isActive: true,
            expiresAt: expiry
        )

        XCTAssertTrue(resolution.isActive)
        XCTAssertEqual(resolution.expiresAt, expiry)
    }

    func testUnknownSourceDoesNotRecoverDuringNormalPolling() {
        XCTAssertFalse(InputSourceRecovery.shouldTreatSourceAsRecoverable(
            nil,
            allowUnknownSourceRecovery: false
        ))
    }

    func testUnknownSourceCanRecoverDuringResumeChecks() {
        XCTAssertTrue(InputSourceRecovery.shouldTreatSourceAsRecoverable(
            nil,
            allowUnknownSourceRecovery: true
        ))
    }

    func testNRIMESourceDoesNotRecoverDuringResumeChecks() {
        XCTAssertFalse(InputSourceRecovery.shouldTreatSourceAsRecoverable(
            InputSourceSelector.visibleInputSourceID,
            allowUnknownSourceRecovery: true
        ))
    }

    // MARK: - Secure input ASCII fallback

    private let nrimeSource = InputSourceSelector.visibleInputSourceID

    func testStepsAsideWhenSecureInputBeginsWhileNRIMEIsActive() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: false, isActive: true,
            currentSourceID: nrimeSource, rememberedSourceID: nil)

        XCTAssertEqual(action, .switchToASCII(remembering: nrimeSource))
    }

    func testDoesNotStepAsideWhenAnotherLayoutIsAlreadyActive() {
        // The user picked a non-NRIME layout themselves — leave it alone, and
        // remember nothing so secure input ending does not move them.
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: false, isActive: true,
            currentSourceID: "com.apple.keylayout.ABC", rememberedSourceID: nil)

        XCTAssertEqual(action, .none)
    }

    func testRestoresRememberedSourceWhenSecureInputEnds() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: true, isActive: false,
            currentSourceID: "com.apple.keylayout.ABC", rememberedSourceID: nrimeSource)

        XCTAssertEqual(action, .restore(nrimeSource))
    }

    func testDoesNotRestoreWhenNothingWasRemembered() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: true, isActive: false,
            currentSourceID: "com.apple.keylayout.ABC", rememberedSourceID: nil)

        XCTAssertEqual(action, .none)
    }

    func testStableSecureInputStateDoesNothing() {
        // Every poll tick lands here — it must not re-issue switches.
        XCTAssertEqual(InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: true, isActive: true,
            currentSourceID: "com.apple.keylayout.ABC", rememberedSourceID: nrimeSource), .none)
        XCTAssertEqual(InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, wasActive: false, isActive: false,
            currentSourceID: nrimeSource, rememberedSourceID: nil), .none)
    }

    func testDisabledSettingNeverActs() {
        XCTAssertEqual(InputSourceRecovery.secureInputAction(
            fallbackEnabled: false, wasActive: false, isActive: true,
            currentSourceID: nrimeSource, rememberedSourceID: nil), .none)
        XCTAssertEqual(InputSourceRecovery.secureInputAction(
            fallbackEnabled: false, wasActive: true, isActive: false,
            currentSourceID: "com.apple.keylayout.ABC", rememberedSourceID: nrimeSource), .none)
    }
}
