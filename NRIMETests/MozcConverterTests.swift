import XCTest
@testable import NRIME

final class MozcConverterTests: XCTestCase {

    func testPrepareForConversionStoresSourceAndClearsTransientState() {
        let converter = MozcConverter()
        let output = makeOutputWithCandidates(["変換"])

        _ = converter.updateFromOutput(output)
        converter.prepareForConversion(hiragana: "へんかん")

        XCTAssertEqual(converter.originalHiragana, "へんかん")
        XCTAssertTrue(converter.currentCandidateStrings.isEmpty)
        XCTAssertNil(converter.currentPreedit)
    }

    func testPreeditOnlyOutputDoesNotCreateSyntheticCandidates() {
        let converter = MozcConverter()
        converter.prepareForConversion(hiragana: "かな")

        let output = makeOutputWithPreedit(["仮名"])
        let result = converter.updateFromOutput(output)

        XCTAssertFalse(result.hasCandidates)
        XCTAssertTrue(converter.currentCandidateStrings.isEmpty)
    }

    private func makeOutputWithCandidates(_ values: [String]) -> Mozc_Commands_Output {
        var output = Mozc_Commands_Output()
        var allCandidates = Mozc_Commands_CandidateList()
        allCandidates.focusedIndex = 0
        allCandidates.candidates = values.enumerated().map { index, value in
            var candidate = Mozc_Commands_CandidateWord()
            candidate.value = value
            candidate.id = Int32(index + 1)
            return candidate
        }
        output.allCandidateWords = allCandidates
        return output
    }

    private func makeOutputWithPreedit(_ values: [String]) -> Mozc_Commands_Output {
        var output = Mozc_Commands_Output()
        var preedit = Mozc_Commands_Preedit()
        preedit.segment = values.map { value in
            var segment = Mozc_Commands_Preedit.Segment()
            segment.value = value
            return segment
        }
        output.preedit = preedit
        return output
    }
}
