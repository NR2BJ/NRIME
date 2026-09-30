import Cocoa
import InputMethodKit
import XCTest
@testable import NRIME

/// Codex Shift+Enter: the commit lands, then Shift+Enter is posted again
/// after a short wait (KeyEventReposter.keyPressWait). Keys typed during the
/// wait are held and posted after the newline, in order.
@MainActor
final class CodexReplayTests: XCTestCase {
    private typealias Sent = (keyCode: UInt16, flags: CGEventFlags)

    private var client: MockTextInputClient!
    private var controller: NRIMEInputController!
    private var sent: [[Sent]] = []

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

    func testReplayWaitsThenSendsShiftEnter() {
        commitWithShiftEnter()

        settle(KeyEventReposter.keyPressWait / 2)
        XCTAssertTrue(sent.isEmpty, "Not before the commit has had time to settle")
        settle(KeyEventReposter.keyPressWait + 0.05)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x24])
        XCTAssertEqual(sent.first?.first?.flags, .maskShift, "A plain Enter would send the message")
        XCTAssertEqual(client.insertedTexts, ["ㄱ"], "No \\n insert — it would send the message in Codex")
    }

    func testKeysTypedDuringTheWaitReachTheAppAfterTheNewline() {
        commitWithShiftEnter()

        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client)) // ㅇ, during the wait
        XCTAssertTrue(controller.handle(key(0x28, "k"), client: client)) // ㅏ
        XCTAssertEqual(client.insertedTexts, ["ㄱ"], "Nothing typed during the wait reaches the app yet…")
        XCTAssertEqual(client.markedString, "", "…not even as a composition, which would land above the newline")

        settle(KeyEventReposter.keyPressWait + 0.1)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x24, 0x02, 0x28], "Newline first, then the keys in order")
    }

    func testKeyInAnotherTextFieldSendsTheNewlineAtOnce() {
        commitWithShiftEnter()

        let otherField = MockTextInputClient()
        XCTAssertFalse(KeyEventReposter.holdForPendingReplay(key(0x02, "d"), client: otherField),
                       "Not typed after that newline — handled normally")
        XCTAssertEqual(sent.map { $0.map(\.keyCode) }, [[0x24]], "…and the newline went out first")
    }

    func testNewlineIsDroppedWhenCodexIsNoLongerInFront() {
        commitWithShiftEnter()
        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client))

        KeyEventReposter.frontmostBundleIDForTesting = .some("com.apple.Safari")
        settle(KeyEventReposter.keyPressWait + 0.1)
        XCTAssertEqual(sent.first?.map(\.keyCode), [0x02],
                       "A stray Shift+Enter must not reach another app; the typed key still goes out")
    }

    /// The waits follow the settings app (the same keys work from Terminal),
    /// fall back to the built-in values when unset, and stay within 0–500 ms.
    func testWaitsFollowTheSetting() {
        let testing = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)!
        defer {
            testing.removeObject(forKey: "newlineInsertWaitMs")
            testing.removeObject(forKey: "newlineKeyPressWaitMs")
        }
        testing.removeObject(forKey: "newlineInsertWaitMs")
        testing.removeObject(forKey: "newlineKeyPressWaitMs")
        XCTAssertEqual(KeyEventReposter.insertWait, 0.02, accuracy: 0.0001)
        XCTAssertEqual(KeyEventReposter.keyPressWait, 0.05, accuracy: 0.0001)

        testing.set(0, forKey: "newlineInsertWaitMs")
        XCTAssertEqual(KeyEventReposter.insertWait, 0, "0 is a real value: no wait")
        testing.set(45, forKey: "newlineKeyPressWaitMs")
        XCTAssertEqual(KeyEventReposter.keyPressWait, 0.045, accuracy: 0.0001)
        testing.set(5000, forKey: "newlineKeyPressWaitMs")
        XCTAssertEqual(KeyEventReposter.keyPressWait, 0.5, accuracy: 0.0001)
    }

    /// The key-press apps are a setting: Codex unless the owner changed the
    /// list (Claude went back to the inserted newline after 1.0.12-beta.7).
    func testKeyPressAppsFollowTheSetting() {
        let testing = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)!
        defer { testing.removeObject(forKey: NewlineKeyPress.appsKey) }
        testing.removeObject(forKey: NewlineKeyPress.appsKey)
        XCTAssertTrue(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.openai.codex"))
        XCTAssertFalse(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.anthropic.claudefordesktop"))
        XCTAssertFalse(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.hnc.Discord"))

        testing.set(["com.hnc.Discord"], forKey: NewlineKeyPress.appsKey)
        XCTAssertTrue(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.hnc.Discord"), "Added in the settings app")
        XCTAssertFalse(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.openai.codex"), "Removed from the list")

        testing.set([String](), forKey: NewlineKeyPress.appsKey)
        XCTAssertFalse(ChromiumDetector.needsNewlineKeyPress(bundleID: "com.openai.codex"), "An empty list stays empty")
    }

    func testWithoutPermissionOnlyTheCommitHappens() {
        KeyEventReposter.postEventAccessForTesting = false
        commitWithShiftEnter()

        XCTAssertTrue(controller.handle(key(0x02, "d"), client: client))
        XCTAssertEqual(client.markedString, "ㅇ", "No replay is waiting, so the key is not held")
        settle(KeyEventReposter.keyPressWait + 0.1)
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
