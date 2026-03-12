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
}
