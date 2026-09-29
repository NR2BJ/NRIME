import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Codex Shift+Enter (2026-09-30): the replayed key waits for its own setting,
/// and keys typed during that wait reach the app after the newline.
@MainActor
final class CodexReplayTests: XCTestCase {
    private typealias Sent = (keyCode: UInt16, flags: CGEventFlags, tag: Int64)

    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!
    private var sent: [[Sent]] = []
    private let testing = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)!

    override func setUp() {
        super.setUp()
        KeyEventReposter.resetPendingForTesting()
        ChromiumDetector.overrideForTesting = true
        ChromiumDetector.newlineQuirkOverrideForTesting = true
        KeyEventReposter.frontmostBundleIDForTesting = .some("com.openai.codex")
        sent = []
        KeyEventReposter.sequenceCaptureForTesting = { [weak self] keys in
            self?.sent.append(keys)
        }
        client = MockTextInputClient()
        controller = NRIMEInputController(server: nil, delegate: nil, client: nil)
        controller.testingClientOverride = client
        StateManager.shared.switchTo(.korean)
    }

    override func tearDown() {
        KeyEventReposter.resetPendingForTesting()
        KeyEventReposter.sequenceCaptureForTesting = nil
        KeyEventReposter.frontmostBundleIDForTesting = nil
        ChromiumDetector.overrideForTesting = nil
        ChromiumDetector.newlineQuirkOverrideForTesting = nil
        testing.removeObject(forKey: "codexNewlineDelay")
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

    /// A key as it comes back after being held: posted with the held-key tag.
    private func released(_ keyCode: UInt16) -> NSEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.setIntegerValueField(.eventSourceUserData, value: KeyEventReposter.heldKeyTag)
        return NSEvent(cgEvent: event)!
    }

    private func settle(_ seconds: TimeInterval) {
        let done = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    /// Type ㄱ, then Shift+Enter: the commit lands and the replay is scheduled.
    private func commitWithShiftEnter() {
        XCTAssertTrue(controller.handle(key(0x0F, "r"), client: client)) // ㄱ
        XCTAssertTrue(controller.handle(key(0x24, "\r", shift: true), client: client))
        XCTAssertEqual(client.insertedTexts, ["ㄱ"])
    }

    func testReplayWaitsForTheCodexSettingNotTheElectronDelay() {
        Settings.shared.codexNewlineDelay = 0.03
        commitWithShiftEnter()

        settle(0.08) // well short of the old fixed 120 ms

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x24])
        XCTAssertEqual(sent.first?.first?.tag, KeyEventReposter.repostTag)
        XCTAssertEqual(sent.first?.first?.flags, .maskShift, "A plain Enter would send the message")
    }

    func testNoWaitIsStoredAsZeroAndIsTheDefault() {
        let originalElectron = testing.object(forKey: "shiftEnterDelay")
        defer { testing.set(originalElectron, forKey: "shiftEnterDelay") }
        testing.removeObject(forKey: "shiftEnterDelay")
        testing.removeObject(forKey: "codexNewlineDelay")
        XCTAssertEqual(Settings.shared.shiftEnterDelay, 0, "Default: no wait")
        XCTAssertEqual(Settings.shared.codexNewlineDelay, 0)

        Settings.shared.shiftEnterDelay = 0.005
        Settings.shared.codexNewlineDelay = 0.01
        XCTAssertEqual(Settings.shared.shiftEnterDelay, 0.005)
        Settings.shared.shiftEnterDelay = 0
        Settings.shared.codexNewlineDelay = 0
        XCTAssertEqual(Settings.shared.shiftEnterDelay, 0, "A stored 0 used to read as unset and bring back 15 ms")
        XCTAssertEqual(Settings.shared.codexNewlineDelay, 0)
    }

    func testNoWaitSendsTheNewlineRightAfterTheKeyBeingHandled() {
        Settings.shared.codexNewlineDelay = 0
        commitWithShiftEnter()

        XCTAssertEqual(sent.count, 0, "Not from inside the Shift+Enter being handled…")
        settle(0.03)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x24], "…but on the next turn")
    }

    func testKeysTypedDuringTheWaitReachTheAppAfterTheNewline() {
        Settings.shared.codexNewlineDelay = 0.1
        commitWithShiftEnter()

        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client)) // ㅇ, during the wait
        XCTAssertTrue(controller.handle(key(0x28, "k"), client: client)) // ㅏ
        XCTAssertEqual(client.insertedTexts, ["ㄱ"], "Nothing typed during the wait reaches the app yet…")
        XCTAssertEqual(client.markedString, "", "…not even as a composition, which would land above the newline")

        settle(0.2)

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x24, 0x02, 0x28], "Newline first, then the keys in order")
        XCTAssertEqual(sent.first?.map(\.tag),
                       [KeyEventReposter.repostTag, KeyEventReposter.heldKeyTag, KeyEventReposter.heldKeyTag])

        // Back from the event tap, the held keys compose as usual.
        XCTAssertTrue(controller.handle(released(0x02), client: client))
        XCTAssertTrue(controller.handle(released(0x28), client: client))
        XCTAssertEqual(client.markedString, "아")
    }

    func testKeyInAnotherTextFieldSendsTheNewlineAtOnce() {
        Settings.shared.codexNewlineDelay = 0.2
        commitWithShiftEnter()

        let otherField = MockTextInputClient()
        XCTAssertFalse(KeyEventReposter.holdForPendingReplay(key(0x02, "d"), client: otherField),
                       "Not typed after that newline — handled normally")
        XCTAssertEqual(sent.map { $0.map(\.keyCode) }, [[0x24]], "…and the newline went out first")
    }

    func testNewlineIsDroppedWhenCodexIsNoLongerInFront() {
        Settings.shared.codexNewlineDelay = 0.05
        commitWithShiftEnter()
        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client))

        KeyEventReposter.frontmostBundleIDForTesting = .some("com.apple.Safari")
        settle(0.15)

        XCTAssertEqual(sent.first?.map(\.keyCode), [0x02],
                       "A stray Shift+Enter must not reach another app; the typed key still goes out")
    }

    func testReplayIsSkippedWithoutPermissionAndNothingIsHeld() {
        KeyEventReposter.postEventAccessForTesting = false
        defer { KeyEventReposter.postEventAccessForTesting = nil }
        commitWithShiftEnter()

        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client))
        XCTAssertEqual(client.markedString, "ㅇ", "No replay is waiting, so the key is not held")
        settle(0.2)
        XCTAssertEqual(sent.count, 0)
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
