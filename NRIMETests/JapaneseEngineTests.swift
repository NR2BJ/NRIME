import XCTest
@testable import NRIME

final class JapaneseEngineTests: XCTestCase {

    func testConversionFallbackPrefersCurrentPreedit() {
        let preedit = makePreedit(["変", "換"])

        let text = JapaneseEngine.conversionFallbackText(
            preedit: preedit,
            originalHiragana: "へんかん"
        )

        XCTAssertEqual(text, "変換")
    }

    func testConversionFallbackUsesOriginalHiraganaWhenPreeditMissing() {
        let text = JapaneseEngine.conversionFallbackText(
            preedit: nil,
            originalHiragana: "かな"
        )

        XCTAssertEqual(text, "かな")
    }

    func testLiveConversionCommitTextAppendsResolvedPendingTail() {
        let text = JapaneseEngine.liveConversionCommitText(
            convertedText: "漢字",
            composedKana: "かんじ",
            flushedText: "かんじん"
        )

        XCTAssertEqual(text, "漢字ん")
    }

    private func makePreedit(_ segments: [String]) -> Mozc_Commands_Preedit {
        var preedit = Mozc_Commands_Preedit()
        preedit.segment = segments.map { value in
            var segment = Mozc_Commands_Preedit.Segment()
            segment.value = value
            return segment
        }
        return preedit
    }
}
