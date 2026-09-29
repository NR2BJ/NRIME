import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Codex Shift+Enter: the commit lands, then Shift+Enter is posted again on
/// the next turn of the run loop — no wait, and nothing held (2026-09-30).
@MainActor
final class CodexReplayTests: XCTestCase {
    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!
    private var sent: [(keyCode: UInt16, flags: CGEventFlags)] = []

    override func setUp() {
        super.setUp()
        ChromiumDetector.overrideForTesting = true
        ChromiumDetector.newlineQuirkOverrideForTesting = true
        sent = []
        KeyEventReposter.captureForTesting = { [weak self] keyCode, flags in
            self?.sent.append((keyCode, flags))
        }
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        StateManager.shared.switchTo(.korean)
    }

    override func tearDown() {
        KeyEventReposter.captureForTesting = nil
        KeyEventReposter.postEventAccessForTesting = nil
        ChromiumDetector.overrideForTesting = nil
        ChromiumDetector.newlineQuirkOverrideForTesting = nil
        StateManager.shared.switchTo(.english)
        controller = nil
        client = nil
        super.tearDown()
    }

    private func key(_ keyCode: UInt16, _ characters: String = "", shift: Bool = false) -> NSEvent {
        let flags: NSEvent.ModifierFlags = shift
            ? NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2) // left shift
            : []
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                windowNumber: 0, context: nil, characters: characters,
                                charactersIgnoringModifiers: characters, isARepeat: false,
                                keyCode: keyCode)!
    }

    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    /// Type ㄱ, then Shift+Enter: the commit lands at once.
    private func commitWithShiftEnter() {
        XCTAssertTrue(controller.handle(key(0x0F, "r"), client: client)) // ㄱ
        XCTAssertTrue(controller.handle(key(0x24, "\r", shift: true), client: client))
        XCTAssertEqual(client.insertedTexts, ["ㄱ"])
    }

    func testShiftEnterIsPostedAgainRightAfterTheKeyBeingHandled() {
        commitWithShiftEnter()

        XCTAssertTrue(sent.isEmpty, "Not from inside the Shift+Enter being handled…")
        settle(0.03)
        XCTAssertEqual(sent.map(\.keyCode), [0x24], "…but on the next turn")
        XCTAssertEqual(sent.first?.flags, .maskShift, "A plain Enter would send the message")
        XCTAssertEqual(client.insertedTexts, ["ㄱ"], "No \\n insert — it would send the message in Codex")
    }

    /// The posted key comes back through the input method like any other:
    /// with nothing composing, it goes on to the app.
    func testThePostedShiftEnterComesBackAndPassesThrough() {
        commitWithShiftEnter()
        settle(0.03)

        XCTAssertFalse(controller.handle(key(0x24, "\r", shift: true), client: client))
        settle(0.03)
        XCTAssertEqual(sent.count, 1, "Passed on, not posted a second time")
    }

    func testWithoutPermissionOnlyTheCommitHappens() {
        KeyEventReposter.postEventAccessForTesting = false
        commitWithShiftEnter()

        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client))
        XCTAssertEqual(client.markedString, "ㅇ", "The next key composes as usual")
        settle(0.05)
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - Dictionary readings with small kana

    func testDictionaryReadingsKeepSmallKanaAndTheLongVowelMark() {
        XCTAssertEqual(UserDictionaryReading.normalized(" チャッキューモツ "), "ちゃっきゅーもつ")
        XCTAssertEqual(UserDictionaryReading.normalized("ﾁｬｯｷｭｰ"), "ちゃっきゅー", "Half-width katakana")
        XCTAssertEqual(UserDictionaryReading.normalized("ヴァー"), "ゔぁー", "ー stays a long-vowel mark")
        XCTAssertEqual(UserDictionaryReading.normalized("ぁぃぅぇぉゃゅょっゎ"), "ぁぃぅぇぉゃゅょっゎ")
    }

    func testRomajiTypesTheReadingsThoseWordsAreSavedUnder() {
        let composer = RomajiComposer()
        for character in "chakkyu-motsu" { _ = composer.input(character) }
        XCTAssertEqual(composer.flush(), "ちゃっきゅーもつ")

        let small = RomajiComposer()
        for character in "xaltuxyolya" { _ = small.input(character) }
        XCTAssertEqual(small.flush(), "ぁっょゃ")
    }
}
