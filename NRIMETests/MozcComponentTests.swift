import CryptoKit
import XCTest
@testable import NRIME

/// Mozc without a new NRIME (2026-09-30): choosing between the bundled engine
/// and downloaded ones, guarding against bad downloads, and the update check.
final class MozcComponentTests: XCTestCase {
    private var downloads: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        downloads = fm.temporaryDirectory.appendingPathComponent("NRIME-components-\(UUID().uuidString)")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        MozcComponents.downloadsDirectoryForTesting = downloads
        MozcComponents.bundledForTesting = .some(Self.fakeBundled)
    }

    override func tearDown() {
        MozcComponents.downloadsDirectoryForTesting = nil
        MozcComponents.bundledForTesting = nil
        MozcEngine.enabledForTesting = false
        try? fm.removeItem(at: downloads)
        super.tearDown()
    }

    private static let fakeBundled = MozcComponent(
        source: .bundled, libraryURL: URL(fileURLWithPath: "/nonexistent/libnrime_mozc.dylib"),
        dataURL: URL(fileURLWithPath: "/nonexistent/mozc.data"),
        commit: "a069a88d4cb5c011de0f9aebb6c149a1c808d904", date: "2026-09-28", version: "3.34.6239.101",
        directory: nil)

    /// A downloaded component with placeholder files.
    @discardableResult
    private func addDownload(commit: String, date: String, version: String = "3.35.1.101",
                             abi: Int = MozcComponents.supportedABI, bad: Bool = false) throws -> URL {
        let directory = downloads.appendingPathComponent(commit)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("lib".utf8).write(to: directory.appendingPathComponent(MozcComponents.libraryName))
        try Data("data".utf8).write(to: directory.appendingPathComponent(MozcComponents.dataName))
        let manifest = MozcComponents.Manifest(abi: abi, commit: commit, date: date, version: version, files: [:])
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(MozcComponents.manifestName))
        if bad {
            try Data().write(to: directory.appendingPathComponent(MozcComponents.State.bad.rawValue))
        }
        return directory
    }

    // MARK: - Choosing

    func testNewerDownloadsComeFirstThenTheBundledEngine() throws {
        try addDownload(commit: "b1", date: "2026-10-10")
        try addDownload(commit: "c2", date: "2026-11-20")
        try addDownload(commit: "old", date: "2026-09-01")               // older than the bundled one
        try addDownload(commit: "bad", date: "2026-12-01", bad: true)     // marked bad
        try addDownload(commit: "abi2", date: "2026-12-24", abi: 2)       // a C API this NRIME does not speak

        let order = MozcComponents.candidates().map(\.commit)

        XCTAssertEqual(order, ["c2", "b1", Self.fakeBundled.commit])
    }

    func testTheSameCommitIsNeverNewer() {
        var same = Self.fakeBundled
        same = MozcComponent(source: .downloaded, libraryURL: same.libraryURL, dataURL: same.dataURL,
                             commit: same.commit, date: "2027-01-01", version: same.version, directory: nil)
        XCTAssertFalse(MozcComponents.isNewer(same, than: Self.fakeBundled))
    }

    // MARK: - Guarding

    func testALoadThatNeverFinishedMarksTheComponentBad() throws {
        let directory = try addDownload(commit: "b1", date: "2026-10-10")
        let component = try XCTUnwrap(MozcComponents.downloaded().first)
        XCTAssertTrue(MozcComponents.beginLoad(component))
        // The process died here: endLoad never ran.

        XCTAssertFalse(MozcComponents.beginLoad(component), "Not tried again after dying in its load")
        XCTAssertTrue(fm.fileExists(atPath: directory.appendingPathComponent("bad").path))
        XCTAssertEqual(MozcComponents.candidates().map(\.commit), [Self.fakeBundled.commit])
    }

    func testThreeStartsInTenMinutesIsACrashLoop() throws {
        try addDownload(commit: "b1", date: "2026-10-10")
        let component = try XCTUnwrap(MozcComponents.downloaded().first)
        let now = Date()

        XCTAssertTrue(MozcComponents.beginLoad(component, now: now.addingTimeInterval(-300)))
        MozcComponents.endLoad(component)
        XCTAssertTrue(MozcComponents.beginLoad(component, now: now.addingTimeInterval(-120)))
        MozcComponents.endLoad(component)
        XCTAssertFalse(MozcComponents.beginLoad(component, now: now), "Third start within ten minutes")
        XCTAssertTrue(MozcComponents.downloaded().isEmpty)
    }

    func testStartsHoursApartAreFine() throws {
        try addDownload(commit: "b1", date: "2026-10-10")
        let component = try XCTUnwrap(MozcComponents.downloaded().first)
        let now = Date()
        for hoursAgo in [5.0, 3.0, 1.0, 0.0] {
            XCTAssertTrue(MozcComponents.beginLoad(component, now: now.addingTimeInterval(-hoursAgo * 3600)))
            MozcComponents.endLoad(component)
        }
    }

    func testPruneKeepsTwoGoodDownloadsAndOnlyTheMarkerOfABadOne() throws {
        try addDownload(commit: "a", date: "2026-10-01")
        try addDownload(commit: "b", date: "2026-10-02")
        try addDownload(commit: "c", date: "2026-10-03")
        let bad = try addDownload(commit: "x", date: "2026-10-04", bad: true)

        MozcComponents.prune(keeping: nil)

        XCTAssertEqual(Set(MozcComponents.downloaded().map(\.commit)), ["b", "c"])
        XCTAssertTrue(fm.fileExists(atPath: bad.appendingPathComponent("bad").path), "Remembered as bad…")
        XCTAssertFalse(fm.fileExists(atPath: bad.appendingPathComponent(MozcComponents.dataName).path),
                       "…without keeping its 19 MB")
        XCTAssertEqual(MozcComponents.badCommits(), ["x"])
    }

    func testABrokenDownloadFallsBackToTheBundledEngine() throws {
        MozcComponents.bundledForTesting = nil // the real bundled engine
        let bundled = try XCTUnwrap(MozcComponents.bundled, "the test host carries the engine")
        let broken = try addDownload(commit: "fffffff", date: "2099-01-01") // "lib" is not a library
        MozcEngine.enabledForTesting = true
        let engine = MozcEngine.makeForTesting()

        XCTAssertTrue(engine.start())

        XCTAssertEqual(engine.active?.commit, bundled.commit)
        XCTAssertTrue(fm.fileExists(atPath: broken.appendingPathComponent("bad").path))
    }

    // MARK: - The update check

    private func release(_ tag: String, asset: String = MozcUpdater.assetName,
                         digest: String? = "sha256:00", draft: Bool = false) -> GitHubRelease {
        let json: [String: Any] = [
            "tag_name": tag, "prerelease": true, "draft": draft,
            "assets": [[
                "name": asset, "size": 1,
                "browser_download_url": "https://github.com/NR2BJ/NRIME/releases/download/\(tag)/\(asset)",
                "digest": digest.map { $0 as Any } ?? NSNull(),
            ]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func testReadsOnlyComponentReleases() {
        let offer = MozcUpdater.offer(from: release("mozc-1-20261120-c2c2c2c"))
        XCTAssertEqual(offer?.abi, 1)
        XCTAssertEqual(offer?.date, "2026-11-20")
        XCTAssertEqual(offer?.commitPrefix, "c2c2c2c")

        XCTAssertNil(MozcUpdater.offer(from: release("v1.0.12-beta.3", asset: "NRIME-1.0.12-beta.3.pkg")),
                     "An app release")
        XCTAssertNil(MozcUpdater.offer(from: release("mozc-1-2026112-c2c2c2c")), "Malformed date")
        XCTAssertNil(MozcUpdater.offer(from: release("mozc-1-20261120-c2c2c2c", asset: "other.zip")))
        XCTAssertNil(MozcUpdater.offer(from: release("mozc-1-20261120-c2c2c2c", digest: nil)),
                     "No digest to check the download against")
        XCTAssertNil(MozcUpdater.offer(from: release("mozc-1-20261120-c2c2c2c", draft: true)))
    }

    func testPicksTheNewestComponentOfThisABIThatIsNotBad() {
        let releases = [
            release("mozc-1-20261010-b1b1b1b"),
            release("mozc-1-20261120-c2c2c2c"),
            release("mozc-2-20261224-d3d3d3d"),
            release("mozc-1-20261201-e4e4e4e"),
        ]
        XCTAssertEqual(MozcUpdater.newest(in: releases, abi: 1, bad: [])?.commitPrefix, "e4e4e4e")
        XCTAssertEqual(MozcUpdater.newest(in: releases, abi: 1, bad: ["e4e4e4e9"])?.commitPrefix, "c2c2c2c")
    }

    func testDownloadsOnlyWhatIsNewerThanEverythingHere() throws {
        let offer = try XCTUnwrap(MozcUpdater.offer(from: release("mozc-1-20261120-c2c2c2c")))
        XCTAssertTrue(MozcUpdater.isWanted(offer, installed: [Self.fakeBundled]))
        let later = MozcComponent(source: .downloaded, libraryURL: Self.fakeBundled.libraryURL,
                                  dataURL: Self.fakeBundled.dataURL, commit: "f0f0f0f0", date: "2026-11-21",
                                  version: "3.35.1.101", directory: nil)
        XCTAssertFalse(MozcUpdater.isWanted(offer, installed: [Self.fakeBundled, later]))
        let same = MozcComponent(source: .downloaded, libraryURL: later.libraryURL, dataURL: later.dataURL,
                                 commit: "c2c2c2c8", date: "2026-11-20", version: "3.35.1.101", directory: nil)
        XCTAssertFalse(MozcUpdater.isWanted(offer, installed: [same]))
    }

    // MARK: - Installing a download

    /// Build an nrime-mozc.zip the way package-component.sh does.
    private func makeZip(commit: String, date: String, abi: Int = 1,
                         tamperLibraryHash: Bool = false) throws -> (zip: URL, digest: String) {
        let stage = downloads.appendingPathComponent(".stage-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let library = Data((0..<4096).map { UInt8($0 % 251) })
        let data = Data((0..<8192).map { UInt8($0 % 241) })
        try library.write(to: stage.appendingPathComponent(MozcComponents.libraryName))
        try data.write(to: stage.appendingPathComponent(MozcComponents.dataName))
        func hex(_ d: Data) -> String { SHA256Hex.of(d) }
        let manifest = MozcComponents.Manifest(
            abi: abi, commit: commit, date: date, version: "3.35.1.101",
            files: [MozcComponents.libraryName: tamperLibraryHash ? String(repeating: "0", count: 64) : hex(library),
                    MozcComponents.dataName: hex(data)])
        try JSONEncoder().encode(manifest).write(to: stage.appendingPathComponent(MozcComponents.manifestName))
        let zip = downloads.appendingPathComponent(".zip-\(UUID().uuidString).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", stage.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        try fm.removeItem(at: stage)
        return (zip, "sha256:" + SHA256Hex.of(try Data(contentsOf: zip)))
    }

    private func offer(commit: String, date: String, digest: String, abi: Int = 1) -> MozcUpdater.Offer {
        MozcUpdater.Offer(abi: abi, date: date, commitPrefix: String(commit.prefix(7)),
                          downloadURL: URL(string: "https://example.invalid/nrime-mozc.zip")!, digest: digest)
    }

    func testInstallsAVerifiedDownloadWhereItIsFound() throws {
        let commit = "c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"
        let (zip, digest) = try makeZip(commit: commit, date: "2026-11-20")

        let component = try MozcUpdater.install(zip: zip, offer: offer(commit: commit, date: "2026-11-20", digest: digest),
                                                into: downloads)

        XCTAssertEqual(component.commit, commit)
        XCTAssertEqual(MozcComponents.downloaded().map(\.commit), [commit])
        XCTAssertEqual(MozcComponents.candidates().first?.commit, commit, "Used from the next start")
    }

    func testRejectsADownloadThatDoesNotMatchItsDigest() throws {
        let commit = "c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"
        let (zip, _) = try makeZip(commit: commit, date: "2026-11-20")
        let wrong = "sha256:" + String(repeating: "a", count: 64)

        XCTAssertThrowsError(try MozcUpdater.install(zip: zip, offer: offer(commit: commit, date: "2026-11-20", digest: wrong),
                                                     into: downloads))
        XCTAssertTrue(MozcComponents.downloaded().isEmpty)
    }

    func testRejectsAFileThatDoesNotMatchTheManifest() throws {
        let commit = "c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"
        let (zip, digest) = try makeZip(commit: commit, date: "2026-11-20", tamperLibraryHash: true)

        XCTAssertThrowsError(try MozcUpdater.install(zip: zip, offer: offer(commit: commit, date: "2026-11-20", digest: digest),
                                                     into: downloads))
        XCTAssertTrue(MozcComponents.downloaded().isEmpty)
    }

    func testRejectsAManifestForAnotherBuild() throws {
        let (zip, digest) = try makeZip(commit: "d3d3d3d3d3d3d3d3d3d3", date: "2026-11-20")

        XCTAssertThrowsError(try MozcUpdater.install(
            zip: zip, offer: offer(commit: "c2c2c2c2c2c2c2c2c2c2", date: "2026-11-20", digest: digest), into: downloads))
    }
}

private enum SHA256Hex {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
