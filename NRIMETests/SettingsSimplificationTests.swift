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

    func testRetiredJapaneseOptionsStayOffWhateverIsStored() throws {
        var stored = JapaneseKeyConfig.default
        stored.prediction = true
        stored.liveConversion = true
        stored.shiftKeyAction = .katakana
        stored.conversionTriggerDownArrow = true
        stored.hiraganaKeyCode = 0x61
        stored.fullKatakanaKeyCode = 0x62
        stored.halfKatakanaKeyCode = 0x64
        stored.fullRomajiKeyCode = 0x65
        stored.halfRomajiKeyCode = 0x6D
        stored.punctuationStyle = .fullWidthWestern
        testing.set(try JSONEncoder().encode(stored), forKey: "japaneseKeyConfig")
        Settings.shared.reloadJapaneseKeyConfig()

        let config = Settings.shared.japaneseKeyConfig
        XCTAssertFalse(config.prediction)
        XCTAssertFalse(config.liveConversion)
        XCTAssertEqual(config.shiftKeyAction, .none)
        XCTAssertFalse(config.conversionTriggerDownArrow)
        XCTAssertNil(config.hiraganaKeyCode)
        XCTAssertNil(config.fullKatakanaKeyCode)
        XCTAssertNil(config.halfKatakanaKeyCode)
        XCTAssertNil(config.fullRomajiKeyCode)
        XCTAssertNil(config.halfRomajiKeyCode)
        XCTAssertEqual(config.punctuationStyle, .fullWidthWestern, "Kept settings are untouched")
    }

    func testDefaultsAlreadyHaveTheRetiredOptionsOff() {
        XCTAssertEqual(JapaneseKeyConfig.default, JapaneseKeyConfig.default.withRetiredOptionsOff())
    }

    func testDownArrowCommitsInsteadOfConverting() {
        var config = JapaneseKeyConfig.default
        config.conversionTriggerDownArrow = true // stored by an older version
        Settings.shared.japaneseKeyConfig = config
        let engine = JapaneseEngine()
        let client = MockTextInputClient()

        XCTAssertTrue(engine.handleEvent(key(0x28), client: client)) // k
        XCTAssertTrue(engine.handleEvent(key(0x00), client: client)) // a → か
        let handled = engine.handleEvent(key(0x7D), client: client)  // ↓

        XCTAssertFalse(handled, "↓ passes through to the app")
        XCTAssertEqual(client.insertedTexts, ["か"], "…after committing what was typed")
        XCTAssertFalse(engine.isInConversionState)
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
