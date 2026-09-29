import Cocoa
import XCTest
@testable import NRIME

/// The 2026-09-29 simplification: settings the owner does not use were removed,
/// and stored values for them must not bring the behaviour back.
final class SettingsSimplificationTests: XCTestCase {
    private var originalConfig: JapaneseKeyConfig!
    private let testing = UserDefaults(suiteName: AppGroupDefaults.testingSuiteName)!

    override func setUp() {
        super.setUp()
        originalConfig = Settings.shared.japaneseKeyConfig
        KeyEventReposter.captureForTesting = { _, _ in }
    }

    override func tearDown() {
        Settings.shared.japaneseKeyConfig = originalConfig
        KeyEventReposter.captureForTesting = nil
        KeyEventReposter.postEventAccessForTesting = nil
        MozcClient.responderForTesting = nil
        MozcEngine.availableForTesting = nil
        for key in ["shortcut_switchKorean", "shortcut_switchJapanese", "shiftDoubleTapEnabled"] {
            testing.removeObject(forKey: key)
        }
        super.tearDown()
    }

    private func key(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = [], time: Double = 10,
                     type: NSEvent.EventType = .keyDown, characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: time,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    // MARK: - Japanese options

    func testSettingsStoredByOlderVersionsStillLoad() throws {
        // A configuration written before the removal still carries the
        // removed keys; they are ignored and the kept settings survive.
        let legacy = """
        {"hiraganaKeyCode":97,"fullKatakanaKeyCode":98,"halfKatakanaKeyCode":100,
         "fullRomajiKeyCode":101,"halfRomajiKeyCode":109,"capsLockAction":"katakana",
         "shiftKeyAction":"romaji","punctuationStyle":"fullWidthWestern","slashToNakaguro":true,
         "yenKeyToYen":true,"fullWidthSpace":true,"liveConversion":true,"prediction":true,
         "candidateFontSize":16,"conversionTriggerSpace":true,"conversionTriggerTab":false,
         "conversionTriggerDownArrow":true}
        """
        testing.set(Data(legacy.utf8), forKey: "japaneseKeyConfig")
        Settings.shared.reloadJapaneseKeyConfig()

        let config = Settings.shared.japaneseKeyConfig
        XCTAssertEqual(config.capsLockAction, .katakana)
        XCTAssertEqual(config.punctuationStyle, .fullWidthWestern)
        XCTAssertTrue(config.fullWidthSpace)
        XCTAssertEqual(config.candidateFontSize, 16)
        XCTAssertFalse(config.conversionTriggerTab)
    }

    func testDownArrowCommitsInsteadOfConverting() {
        Settings.shared.japaneseKeyConfig = .default
        let engine = JapaneseEngine()
        let client = MockTextInputClient()

        XCTAssertTrue(engine.handleEvent(key(0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(key(0x00), client: client)) // a → か
        let handled = engine.handleEvent(key(0x7D), client: client)  // ↓

        XCTAssertFalse(handled, "↓ passes through to the app")
        XCTAssertEqual(client.insertedTexts, ["か"], "…after committing what was typed")
        XCTAssertFalse(engine.isInConversionState)
    }

    func testConversionKeepsTheReadingWhenMozcIsUnavailable() {
        MozcEngine.availableForTesting = false
        Settings.shared.japaneseKeyConfig = .default
        let engine = JapaneseEngine()
        let client = MockTextInputClient()
        XCTAssertTrue(engine.handleEvent(key(0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(key(0x00), client: client)) // a → か

        let start = Date()
        XCTAssertTrue(engine.handleEvent(key(0x31, characters: " "), client: client)) // Space

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1, "Nothing waits for Mozc")
        XCTAssertEqual(client.insertedTexts, [], "Nothing is committed…")
        XCTAssertEqual(client.markedString, "か", "…the reading stays, and Enter still commits it")
        XCTAssertFalse(engine.isInConversionState)
    }

    /// An engine showing 日本語 converted from にほんご.
    private func engineConvertingNihongo() -> JapaneseEngine {
        let engine = JapaneseEngine()
        var output = Mozc_Commands_Output()
        var preedit = Mozc_Commands_Preedit()
        preedit.segment = ["日本", "語"].map { value in
            var segment = Mozc_Commands_Preedit.Segment()
            segment.value = value
            return segment
        }
        output.preedit = preedit
        engine.mozcConverter.prepareForConversion(hiragana: "にほんご")
        _ = engine.mozcConverter.updateFromOutput(output)
        engine.markConvertingForTesting()
        return engine
    }

    func testModeSwitchDuringConversionCommitsWhatIsOnScreenAtOnce() {
        Settings.shared.japaneseKeyConfig = .default
        let engine = engineConvertingNihongo()
        let client = MockTextInputClient()

        let start = Date()
        engine.forceCommit(client: client)

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        XCTAssertEqual(client.insertedTexts, ["日本語"])
        XCTAssertFalse(engine.isInConversionState)
        XCTAssertFalse(engine.mozcConverter.isConverting,
                       "Nothing is left for a following reset to cancel")
    }

    func testConfirmedWordSurvivesAnAnswerWithoutResult() {
        // After a server restart the session is stale: Mozc answers the submit
        // with an error and no result. The word on screen is still committed,
        // not the reading it was converted from.
        MozcClient.responderForTesting = { input in
            var output = Mozc_Commands_Output()
            switch input.type {
            case .createSession:
                output.id = 1
            case .sendCommand:
                output.errorCode = .sessionFailure
            default:
                break
            }
            return output
        }
        let engine = engineConvertingNihongo()

        XCTAssertEqual(engine.mozcConverter.commit(), "日本語")
        XCTAssertFalse(engine.mozcConverter.isConverting)
    }

    func testConfirmedWordSurvivesNoAnswer() {
        // Nothing answers under tests unless a responder is set.
        XCTAssertEqual(engineConvertingNihongo().mozcConverter.commit(), "日本語")
        XCTAssertEqual(engineConvertingNihongo().mozcConverter.commit(fallback: "二本後"), "二本後",
                       "The candidate panel's selection, when given, is committed instead")
    }

    func testTheInputMethodStartsInKorean() {
        XCTAssertEqual(StateManager.initialMode, .korean)
    }

    // MARK: - Shortcuts

    func testStoredDirectSwitchShortcutsDoNothing() throws {
        let rightShiftOne = ShortcutConfig(
            keyCode: 0x12, modifierKeyCode: ShortcutConfig.keyCodeRightShift,
            modifiers: UInt(NSEvent.ModifierFlags.shift.rawValue),
            isModifierOnlyTap: false, label: "Right Shift + 1")
        testing.set(try JSONEncoder().encode(rightShiftOne), forKey: "shortcut_switchKorean")
        let handler = ShortcutHandler()
        var fired: [ShortcutHandler.Action] = []
        handler.onAction = { fired.append($0); return true }
        let rightShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x4)

        _ = handler.handleEvent(key(0x3C, flags: rightShift, time: 10, type: .flagsChanged))
        let consumed = handler.handleEvent(key(0x12, flags: rightShift, time: 10.05, characters: "!"))

        XCTAssertFalse(consumed, "Right Shift + 1 types ! again")
        XCTAssertEqual(fired, [])
    }

    func testDoubleShiftTapNoLongerTogglesCapsLock() {
        testing.set(true, forKey: "shiftDoubleTapEnabled") // stored by an older version
        let handler = ShortcutHandler()
        let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2)
        // Left Shift is not a registered tap key in the default shortcuts.
        for start in [10.0, 10.15] {
            _ = handler.handleEvent(key(0x38, flags: leftShift, time: start, type: .flagsChanged))
            let consumed = handler.handleEvent(key(0x38, time: start + 0.05, type: .flagsChanged))
            XCTAssertFalse(consumed, "The second tap used to toggle Caps Lock")
        }
    }

    // MARK: - Reposting without permission

    func testShortcutReachesTheAppWhenEventsCannotBePosted() {
        KeyEventReposter.postEventAccessForTesting = false
        let engine = KoreanEngine()
        let client = MockTextInputClient()
        XCTAssertTrue(engine.handleEvent(key(0x0F), client: client)) // ㄱ
        XCTAssertTrue(engine.handleEvent(key(0x28), client: client)) // 가

        let handled = engine.handleEvent(key(0x00, flags: .command, characters: "a"), client: client)

        XCTAssertFalse(handled, "A repost that would be dropped must not swallow Cmd+A")
        XCTAssertEqual(client.insertedTexts, ["가"])
    }

    func testShortcutIsRepostedWhenEventsCanBePosted() {
        KeyEventReposter.postEventAccessForTesting = true
        var reposted: [UInt16] = []
        KeyEventReposter.captureForTesting = { keyCode, _ in reposted.append(keyCode) }
        let engine = KoreanEngine()
        let client = MockTextInputClient()
        XCTAssertTrue(engine.handleEvent(key(0x0F), client: client))
        XCTAssertTrue(engine.handleEvent(key(0x28), client: client))

        XCTAssertTrue(engine.handleEvent(key(0x00, flags: .command, characters: "a"), client: client))

        let done = expectation(description: "repost")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(reposted, [0x00])
    }

    // MARK: - Permission status

    func testPermissionStatusRoundTrips() {
        let status = PermissionStatus(postEvents: true, accessibility: false,
                                      checkedAt: Date(timeIntervalSince1970: 1_800_000_000))
        Settings.shared.permissionStatus = status
        XCTAssertEqual(Settings.shared.permissionStatus, status)
    }
}
