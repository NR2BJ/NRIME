import XCTest
@testable import NRIME

final class HanjaSelectionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.nrime.hanja.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRememberedCandidateMovesToFront() {
        let store = HanjaSelectionStore(defaults: defaults)
        let results: [(hanja: String, meaning: String)] = [
            ("社", "company"),
            ("寫", "copy"),
            ("舍", "hut"),
        ]

        store.remember(hanja: "寫", for: "사")
        let prioritized = store.prioritize(results, for: "사")

        XCTAssertEqual(prioritized.map(\.hanja), ["寫", "社", "舍"])
    }

    func testRememberingNewChoiceReplacesOldChoiceForSameHangul() {
        let store = HanjaSelectionStore(defaults: defaults)

        store.remember(hanja: "社", for: "사")
        store.remember(hanja: "寫", for: "사")

        XCTAssertEqual(store.preferredHanja(for: "사"), "寫")
    }

    func testStoreTrimsOlderEntriesWhenCapacityExceeded() {
        let store = HanjaSelectionStore(defaults: defaults, maxEntries: 2)

        store.remember(hanja: "一", for: "일")
        store.remember(hanja: "二", for: "이")
        store.remember(hanja: "三", for: "삼")

        XCTAssertNil(store.preferredHanja(for: "일"))
        XCTAssertEqual(store.preferredHanja(for: "이"), "二")
        XCTAssertEqual(store.preferredHanja(for: "삼"), "三")
    }
}
