import XCTest
@testable import NRIME

final class SemanticVersionTests: XCTestCase {

    // MARK: - Parsing

    func testParsesPlainAndTaggedVersions() {
        XCTAssertEqual(SemanticVersion("1.0.9")?.description, "1.0.9")
        XCTAssertEqual(SemanticVersion("v1.0.9")?.description, "1.0.9")
        XCTAssertEqual(SemanticVersion("1.0.9-beta.2")?.description, "1.0.9-beta.2")
        XCTAssertEqual(SemanticVersion("v1.0.9-beta.2")?.description, "1.0.9-beta.2")
    }

    func testBuildMetadataIsIgnored() {
        let version = SemanticVersion("1.0.9+build.77")
        XCTAssertEqual(version?.description, "1.0.9")
        XCTAssertFalse(version?.isPrerelease ?? true)
    }

    func testRejectsVersionsWithoutNumericCore() {
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
    }

    func testPrereleaseFlag() {
        XCTAssertFalse(SemanticVersion("1.0.9")?.isPrerelease ?? true)
        XCTAssertTrue(SemanticVersion("1.0.9-beta.1")?.isPrerelease ?? false)
    }

    // MARK: - Ordering

    func testCoreVersionOrdering() {
        XCTAssertTrue(version("1.0.9") > version("1.0.8"))
        XCTAssertTrue(version("1.1.0") > version("1.0.99"))
        XCTAssertTrue(version("2.0.0") > version("1.9.9"))
    }

    func testMissingComponentsCompareAsZero() {
        XCTAssertTrue(version("1.1") > version("1.0.9"))
        XCTAssertEqual(version("1.0"), version("1.0.0"))
    }

    func testReleaseOutranksPrereleaseOfSameVersion() {
        // The rule that lets a beta user move up to the final build.
        XCTAssertTrue(version("1.0.9") > version("1.0.9-beta.2"))
        XCTAssertTrue(version("1.0.9-beta.2") < version("1.0.9"))
    }

    func testPrereleaseIterationsOrderNumerically() {
        XCTAssertTrue(version("1.0.9-beta.2") > version("1.0.9-beta.1"))
        // Numeric identifiers compare as numbers, not strings (10 > 9).
        XCTAssertTrue(version("1.0.9-beta.10") > version("1.0.9-beta.9"))
    }

    func testPrereleaseOutranksOlderRelease() {
        XCTAssertTrue(version("1.0.9-beta.1") > version("1.0.8"))
    }

    func testAlphanumericIdentifiersOutrankNumericOnes() {
        XCTAssertTrue(version("1.0.9-rc.1") > version("1.0.9-beta.1"))
        XCTAssertTrue(version("1.0.9-beta") > version("1.0.9-1"))
    }

    func testShorterPrereleaseListRanksLower() {
        XCTAssertTrue(version("1.0.9-beta.1") > version("1.0.9-beta"))
    }

    // MARK: - isNewer

    func testIsNewerDrivesTheUpdatePrompt() {
        XCTAssertTrue(SemanticVersion.isNewer(remote: "1.0.9", than: "1.0.8"))
        XCTAssertFalse(SemanticVersion.isNewer(remote: "1.0.8", than: "1.0.9"))
        XCTAssertFalse(SemanticVersion.isNewer(remote: "1.0.9", than: "1.0.9"))
    }

    func testIsNewerAcrossChannels() {
        // Beta user on 1.0.9-beta.1 sees both the next beta and the final release.
        XCTAssertTrue(SemanticVersion.isNewer(remote: "1.0.9-beta.2", than: "1.0.9-beta.1"))
        XCTAssertTrue(SemanticVersion.isNewer(remote: "1.0.9", than: "1.0.9-beta.1"))
        // A stable user is never offered a prerelease of the version they run.
        XCTAssertFalse(SemanticVersion.isNewer(remote: "1.0.9-beta.1", than: "1.0.9"))
    }

    func testIsNewerTreatsUnparsableInputAsNoUpdate() {
        XCTAssertFalse(SemanticVersion.isNewer(remote: "latest", than: "1.0.8"))
        XCTAssertFalse(SemanticVersion.isNewer(remote: "1.0.9", than: "unknown"))
    }

    private func version(_ raw: String) -> SemanticVersion {
        guard let parsed = SemanticVersion(raw) else {
            XCTFail("Failed to parse version: \(raw)")
            fatalError("Failed to parse version: \(raw)")
        }
        return parsed
    }
}
