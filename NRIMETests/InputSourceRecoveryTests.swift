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
    private let abc = "com.apple.keylayout.ABC"

    func testStepsAsideForAuthenticationUIWhileNRIMEIsActive() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: true,
            currentSourceID: nrimeSource, rememberedSourceID: nil,
            secondsSinceSteppedAside: nil)

        XCTAssertEqual(action, .switchToASCII(remembering: nrimeSource))
    }

    /// The regression that shipped in 1.0.11-beta.5: a chat app held secure
    /// input for hours, the input source was swapped to ABC, and with NRIME no
    /// longer selected it received no events — so language hotkeys died.
    func testOrdinaryAppHoldingSecureInputNeverTakesTheKeyboard() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: false,
            currentSourceID: nrimeSource, rememberedSourceID: nil,
            secondsSinceSteppedAside: nil)

        XCTAssertEqual(action, .none)
    }

    func testDoesNotStepAsideWhenAnotherLayoutIsAlreadyActive() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: true,
            currentSourceID: abc, rememberedSourceID: nil,
            secondsSinceSteppedAside: nil)

        XCTAssertEqual(action, .none)
    }

    func testRestoresOnceAuthenticationUIReleasesSecureInput() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: false,
            currentSourceID: abc, rememberedSourceID: nrimeSource,
            secondsSinceSteppedAside: 3)

        XCTAssertEqual(action, .restore(nrimeSource))
    }

    func testStaysAsideWhileAuthenticationUIStillHoldsIt() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: true,
            currentSourceID: abc, rememberedSourceID: nrimeSource,
            secondsSinceSteppedAside: 3)

        XCTAssertEqual(action, .none)
    }

    /// Backstop: even a panel that never releases cannot keep the keyboard.
    func testRestoresAfterTheCapEvenIfStillHeld() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: true,
            currentSourceID: abc, rememberedSourceID: nrimeSource,
            secondsSinceSteppedAside: InputSourceRecovery.maxStepAsideDuration + 1)

        XCTAssertEqual(action, .restore(nrimeSource))
    }

    /// Losing the stepped-aside timestamp (input method restarted) must resolve
    /// to restoring, never to staying parked on ASCII forever.
    func testMissingTimestampRestoresRatherThanStranding() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: true, heldByAuthenticationUI: true,
            currentSourceID: abc, rememberedSourceID: nrimeSource,
            secondsSinceSteppedAside: nil)

        XCTAssertEqual(action, .restore(nrimeSource))
    }

    func testTurningTheSettingOffWhileAsideRestores() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: false, heldByAuthenticationUI: true,
            currentSourceID: abc, rememberedSourceID: nrimeSource,
            secondsSinceSteppedAside: 1)

        XCTAssertEqual(action, .restore(nrimeSource))
    }

    func testDisabledSettingNeverStepsAside() {
        let action = InputSourceRecovery.secureInputAction(
            fallbackEnabled: false, heldByAuthenticationUI: true,
            currentSourceID: nrimeSource, rememberedSourceID: nil,
            secondsSinceSteppedAside: nil)

        XCTAssertEqual(action, .none)
    }

    // MARK: - Composition suppression

    func testSuppressesCompositionWhenAuthenticationUIHoldsSecureInput() {
        XCTAssertTrue(SecureInputDetector.shouldSuppressComposition(
            holderBundleID: "com.apple.SecurityAgent", frontmostBundleID: "com.apple.Safari"))
    }

    func testSuppressesCompositionWhenTheHolderIsFrontmost() {
        // The password field is plausibly the one being typed into.
        XCTAssertTrue(SecureInputDetector.shouldSuppressComposition(
            holderBundleID: "com.apple.Safari", frontmostBundleID: "com.apple.Safari"))
    }

    func testKeepsComposingWhenABackgroundAppHoldsSecureInput() {
        // The case that broke Korean input for hours: holder is not frontmost,
        // so typing here has nothing to do with its password field.
        XCTAssertFalse(SecureInputDetector.shouldSuppressComposition(
            holderBundleID: "com.anthropic.claudefordesktop", frontmostBundleID: "com.apple.Safari"))
    }

    func testSuppressesCompositionWhenTheHolderCannotBeIdentified() {
        XCTAssertTrue(SecureInputDetector.shouldSuppressComposition(
            holderBundleID: nil, frontmostBundleID: "com.apple.Safari"))
    }
}
