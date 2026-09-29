import XCTest
@testable import NRIME

/// Mozc running inside the input method (2026-09-30): real conversions through
/// NRIME's own converter, with a throwaway profile — never the owner's
/// learning or dictionary.
final class MozcEmbeddedTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        MozcEngine.enabledForTesting = true
        try XCTSkipUnless(MozcEngine.shared.isAvailable, "mozc.data missing — run Tools/mozc/build.sh")
    }

    override func tearDown() {
        MozcEngine.enabledForTesting = false
        super.tearDown()
    }

    override class func tearDown() {
        MozcEngine.shared.sync()
        try? FileManager.default.removeItem(at: MozcEngine.testProfileDirectory)
        super.tearDown()
    }

    func testTheEngineUsesAThrowawayProfileUnderTests() {
        XCTAssertEqual(MozcEngine.profileDirectory, MozcEngine.testProfileDirectory)
        XCTAssertFalse(MozcEngine.profileDirectory.path.contains("Application Support/Mozc"))
    }

    func testConvertsInProcessWithoutWaiting() {
        let converter = MozcConverter()
        defer { converter.reset() }

        let start = Date()
        XCTAssertTrue(converter.convert(hiragana: "にほんご"))

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertTrue(converter.currentCandidateStrings.contains("日本語"),
                      "\(converter.currentCandidateStrings.prefix(5))")
    }

    func testUserDictionaryWordsWithSmallKanaAndTheLongVowelMarkAreFound() throws {
        // ゃ っ and ー in the reading: the words that never turned up in NRIME.
        let words = [("ちゃっきゅーもつ", "茶っ究ー津"), ("くもつくもつ", "蜘蛛津雲津")]
        let converter = MozcConverter()
        func candidates(for reading: String) -> [String] {
            defer { converter.reset() }
            guard converter.convert(hiragana: reading) else { return [] }
            return converter.currentCandidateStrings
        }
        for (reading, word) in words {
            XCTAssertFalse(candidates(for: reading).contains(word), "Must not be known before it is added")
        }

        let file = MozcEngine.testProfileDirectory.appendingPathComponent("user_dictionary.db")
        try Self.userDictionary(words).serializedData().write(to: file)
        defer {
            try? FileManager.default.removeItem(at: file)
            MozcEngine.shared.reloadUserDictionary()
        }
        MozcEngine.shared.reloadUserDictionary()

        // Mozc reads the dictionary in the background: give it a moment.
        var found = false
        for _ in 0..<40 where !found {
            Thread.sleep(forTimeInterval: 0.05)
            found = words.allSatisfy { reading, word in candidates(for: reading).contains(word) }
        }
        XCTAssertTrue(found, "Words added to the user dictionary are conversion candidates after a reload")
    }

    func testLearningIsSavedShortlyAfterACommit() {
        // mozc_server saved learning on a watchdog timer; nothing else would
        // before an update's killall.
        let originalDelay = MozcEngine.syncDelay
        MozcEngine.syncDelay = 0.05
        defer { MozcEngine.syncDelay = originalDelay }
        let converter = MozcConverter()
        let savesBefore = MozcEngine.shared.syncCountForTesting

        XCTAssertTrue(converter.convert(hiragana: "がっこう"))
        XCTAssertNotNil(converter.commit())
        let saved = expectation(description: "saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { saved.fulfill() }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(MozcEngine.shared.syncCountForTesting, savesBefore + 1, "One save for the commit")
    }

    func testReportsItsVersion() {
        let version = String(cString: nrime_mozc_version())
        XCTAssertEqual(version.split(separator: ".").count, 4, version)
    }

    private static func userDictionary(_ words: [(String, String)]) -> Mozc_UserDictionary_UserDictionaryStorage {
        var dictionary = Mozc_UserDictionary_UserDictionary()
        dictionary.id = 1
        dictionary.name = "NRIME tests"
        dictionary.entries = words.map { reading, word in
            var entry = Mozc_UserDictionary_UserDictionary.Entry()
            entry.key = reading
            entry.value = word
            entry.pos = .noun
            return entry
        }
        var storage = Mozc_UserDictionary_UserDictionaryStorage()
        storage.dictionaries = [dictionary]
        return storage
    }
}
