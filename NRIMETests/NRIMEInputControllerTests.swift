import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

@MainActor
final class NRIMEInputControllerTests: XCTestCase {

    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!
    private var originalToggleEnglish: ShortcutConfig!
    private var originalSwitchKorean: ShortcutConfig!
    private var originalSwitchJapanese: ShortcutConfig!
    private var originalHanjaConvert: ShortcutConfig!

    override func setUp() {
        super.setUp()
        originalToggleEnglish = Settings.shared.shortcut(for: "toggleEnglish")
        originalSwitchKorean = Settings.shared.shortcut(for: "switchKorean")
        originalSwitchJapanese = Settings.shared.shortcut(for: "switchJapanese")
        originalHanjaConvert = Settings.shared.shortcut(for: "hanjaConvert")
        Settings.shared.setShortcut(.defaultToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(.defaultSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(.defaultSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(.defaultHanjaConvert, for: "hanjaConvert")
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        ensureCandidatePanel()
        NSApp.candidatePanel?.hide()
        StateManager.shared.switchTo(.english)
        InputSourceRecovery.shared.userInitiatedSwitch = false
    }

    override func tearDown() {
        NSApp.candidatePanel?.hide()
        StateManager.shared.switchTo(.english)
        InputSourceRecovery.shared.userInitiatedSwitch = false
        Settings.shared.setShortcut(originalToggleEnglish, for: "toggleEnglish")
        Settings.shared.setShortcut(originalSwitchKorean, for: "switchKorean")
        Settings.shared.setShortcut(originalSwitchJapanese, for: "switchJapanese")
        Settings.shared.setShortcut(originalHanjaConvert, for: "hanjaConvert")
        controller = nil
        client = nil
        super.tearDown()
    }

    func testSettingsClientBypassesControllerHandling() {
        client.bundleID = "com.nrime.settings"
        StateManager.shared.switchTo(.korean)

        let handled = controller.handle(keyEvent(keyCode: 0x0F), client: client) // r

        XCTAssertFalse(handled)
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.insertedTexts, [])
    }

    func testShortcutSwitchToJapaneseCommitsKoreanCompositionFirst() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")

        let handled = controller.handle(
            keyEvent(keyCode: 0x13, characters: "2", modifiers: [.shift]),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["가"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(StateManager.shared.currentMode, .japanese)
    }

    func testSpaceCommitsKoreanCompositionThroughController() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")

        let handled = controller.handle(keyEvent(keyCode: 0x31, characters: " "), client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedTexts, ["가"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.composedText, "가")
        XCTAssertFalse(NSApp.candidatePanel?.isVisible() ?? true)
    }

    func testEnterCommitsJapaneseCompositionThroughController() {
        StateManager.shared.switchTo(.japanese)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x00), client: client)) // a
        XCTAssertEqual(client.markedString, "か")

        let handled = controller.handle(keyEvent(keyCode: 0x24, characters: "\r"), client: client)

        // Enter while composing: commit text, consumed (return true)
        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedTexts, ["か"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.composedText, "か")
    }

    func testHanjaShortcutShowsPanelAndEscapeRestoresSource() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x05), client: client)) // g
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x01), client: client)) // s
        XCTAssertEqual(client.markedString, "한")

        XCTAssertTrue(controller.handle(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.option]),
            client: client
        ))
        XCTAssertTrue(NSApp.candidatePanel?.isVisible() ?? false)

        let handled = controller.handle(keyEvent(keyCode: 0x35), client: client)

        XCTAssertTrue(handled)
        XCTAssertFalse(NSApp.candidatePanel?.isVisible() ?? true)
        XCTAssertEqual(client.markedString, "한")
        XCTAssertEqual(client.insertedTexts, [])
    }

    func testHanjaPanelSpaceCommitsSourceAndClosesPanel() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x05), client: client)) // g
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x01), client: client)) // s
        XCTAssertEqual(client.markedString, "한")

        XCTAssertTrue(controller.handle(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.option]),
            client: client
        ))
        XCTAssertTrue(NSApp.candidatePanel?.isVisible() ?? false)

        let handled = controller.handle(keyEvent(keyCode: 0x31, characters: " "), client: client)

        XCTAssertFalse(handled)
        XCTAssertFalse(NSApp.candidatePanel?.isVisible() ?? true)
        XCTAssertEqual(client.insertedTexts, ["한"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.composedText, "한")
    }

    func testDeactivateServerForTestingCommitsCompositionAndHidesPanel() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x05), client: client)) // g
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x01), client: client)) // s
        XCTAssertTrue(controller.handle(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.option]),
            client: client
        ))
        XCTAssertTrue(NSApp.candidatePanel?.isVisible() ?? false)

        controller.deactivateServerForTesting(sender: client)

        XCTAssertTrue(InputSourceRecovery.shared.userInitiatedSwitch)
        XCTAssertFalse(NSApp.candidatePanel?.isVisible() ?? true)
        XCTAssertEqual(client.insertedTexts, ["한"])
        XCTAssertEqual(client.markedString, "")
    }

    // MARK: - Shift+Enter & Cmd+A Passthrough Tests

    func testShiftEnterWhileKoreanComposingConsumedForRepost() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r → ㄱ
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k → 가
        XCTAssertEqual(client.markedString, "가")

        let handled = controller.handle(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.shift]),
            client: client
        )

        // Consumed: text committed async, Shift+Enter re-posted via CGEvent
        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedString, "")
    }

    func testCmdAWhileKoreanComposingConsumedForRepost() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")

        let handled = controller.handle(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        // Consumed: text committed async, Cmd+A re-posted via CGEvent
        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedString, "")
    }

    func testCmdAWhileKoreanNotComposingPassesThrough() {
        StateManager.shared.switchTo(.korean)

        let handled = controller.handle(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedTexts, [])
    }

    func testShiftEnterWhileJapaneseComposingConsumedForRepost() {
        StateManager.shared.switchTo(.japanese)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x00), client: client)) // a → か
        XCTAssertEqual(client.markedString, "か")

        let handled = controller.handle(
            keyEvent(keyCode: 0x24, characters: "\r", modifiers: [.shift]),
            client: client
        )

        // Consumed: text committed async, Shift+Enter re-posted via CGEvent
        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedString, "")
    }

    func testCmdAWhileJapaneseComposingConsumedForRepost() {
        StateManager.shared.switchTo(.japanese)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x00), client: client)) // a → か
        XCTAssertEqual(client.markedString, "か")

        let handled = controller.handle(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        // Consumed: text committed async, Cmd+A re-posted via CGEvent
        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedString, "")
    }

    func testCmdAWhileJapaneseNotComposingPassesThrough() {
        StateManager.shared.switchTo(.japanese)

        let handled = controller.handle(
            keyEvent(keyCode: 0x00, characters: "a", modifiers: [.command]),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedTexts, [])
    }

    // MARK: - Mouse Click Tests

    func testMouseClickCommitUsesCachedClient() {
        StateManager.shared.switchTo(.korean)

        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x0F), client: client)) // r
        XCTAssertTrue(controller.handle(keyEvent(keyCode: 0x28), client: client)) // k
        XCTAssertEqual(client.markedString, "가")

        controller.commitOnMouseClickForTesting()

        XCTAssertEqual(client.insertedTexts, ["가"])
        XCTAssertEqual(client.markedString, "")
        XCTAssertEqual(client.composedText, "가")
    }

    private func ensureCandidatePanel() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            XCTFail("Expected AppDelegate to be installed for candidate panel access")
            return
        }
        if appDelegate.candidatePanel == nil {
            appDelegate.candidatePanel = CandidatePanel()
        }
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create NSEvent")
            fatalError("Failed to create NSEvent")
        }
        return event
    }

}
