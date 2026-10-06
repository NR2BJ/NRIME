import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Picking a mode from the menu bar menu (AppDelegate → chooseModeFromMenu).
/// The current input source and "added" are test seams, and selecting NRIME
/// is only recorded: a test must never change the Mac's input source.
@MainActor
final class MenuModeChoiceTests: XCTestCase {
    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!

    override func setUp() {
        super.setUp()
        StateManager.shared.resetForTesting()
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        InputSourceSelector.currentSourceIDForTesting = InputSourceSelector.visibleInputSourceID
        InputSourceSelector.addedForTesting = true
        InputSourceSelector.selectionRequestsForTesting = []
        StateManager.shared.switchTo(.korean)
    }

    override func tearDown() {
        InputSourceSelector.currentSourceIDForTesting = nil
        InputSourceSelector.addedForTesting = nil
        InputSourceSelector.selectionRequestsForTesting = []
        StateManager.shared.resetForTesting()
        controller = nil
        client = nil
        super.tearDown()
    }

    private func typeGa() {
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")
    }

    /// While NRIME is the input source, what is being composed is committed
    /// first, as a switch shortcut does.
    func testChoiceCommitsTheCompositionThenSwitches() {
        typeGa()

        NRIMEInputController.chooseMode(.japanese, fromMenuWith: controller)

        XCTAssertEqual(client.insertedTexts, ["가"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
        XCTAssertEqual(InputSourceSelector.selectionRequestsForTesting, [],
                       "NRIME is already the input source")
    }

    /// From another input source NRIME is selected, and the field — where that
    /// input method may be composing — is left alone.
    func testChoiceFromAnotherSourceSelectsNRIMEAndLeavesTheFieldAlone() {
        typeGa()
        InputSourceSelector.currentSourceIDForTesting = "com.apple.keylayout.ABC"

        NRIMEInputController.chooseMode(.japanese, fromMenuWith: controller)

        XCTAssertEqual(client.insertedTexts, [], "Not NRIME's text to commit")
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
        XCTAssertEqual(InputSourceSelector.selectionRequestsForTesting,
                       [InputSourceSelector.visibleInputSourceID])
    }

    /// Choosing the mode NRIME is already in still brings NRIME back.
    func testChoiceOfTheSameModeStillSelectsNRIME() {
        InputSourceSelector.currentSourceIDForTesting = "com.apple.keylayout.ABC"

        NRIMEInputController.chooseMode(.korean, fromMenuWith: controller)

        XCTAssertEqual(StateManager.shared.currentMode, .korean)
        XCTAssertEqual(InputSourceSelector.selectionRequestsForTesting,
                       [InputSourceSelector.visibleInputSourceID])
    }

    /// An input method the owner never added is not selected behind their back.
    func testChoiceDoesNotSelectNRIMEUnlessAdded() {
        InputSourceSelector.currentSourceIDForTesting = "com.apple.keylayout.ABC"
        InputSourceSelector.addedForTesting = false

        NRIMEInputController.chooseMode(.english, fromMenuWith: controller)

        XCTAssertEqual(StateManager.shared.currentMode, .english, "The mode still changes")
        XCTAssertEqual(InputSourceSelector.selectionRequestsForTesting, [])
    }

    /// Nothing activated yet (no controller): the mode still changes.
    func testChoiceWithoutAControllerStillSwitches() {
        NRIMEInputController.chooseMode(.japanese, fromMenuWith: nil)

        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    /// "Added" is read from the list System Settings keeps: NRIME's visible
    /// mode must be on it.
    func testAddedIsReadFromSystemSettingsList() {
        XCTAssertTrue(InputSourceSelector.enabledListContainsNRIME([
            ["Bundle ID": "com.nrime.inputmethod.app", "InputSourceKind": "Keyboard Input Method"],
            ["Bundle ID": "com.nrime.inputmethod.app", "Input Mode": "com.nrime.inputmethod.app.en",
             "InputSourceKind": "Input Mode"],
        ]))
        XCTAssertFalse(InputSourceSelector.enabledListContainsNRIME([
            ["Bundle ID": "com.cssgsg.inputmethod.app", "InputSourceKind": "Keyboard Input Method"],
        ]))
        XCTAssertFalse(InputSourceSelector.enabledListContainsNRIME([]))
        XCTAssertFalse(InputSourceSelector.enabledListContainsNRIME(nil), "Unreadable counts as not added")
    }

    private func keyEvent(keyCode: UInt16) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        ) else {
            XCTFail("Failed to create NSEvent")
            fatalError("Failed to create NSEvent")
        }
        return event
    }
}
