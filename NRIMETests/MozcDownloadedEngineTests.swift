import CryptoKit
import XCTest
@testable import NRIME

/// The whole way a Mozc update reaches this Mac: the component zip the
/// workflow publishes (Tools/mozc/package-component.sh) is verified,
/// installed where MozcComponents finds it, preferred over the bundled
/// engine, loaded from there, and converts.
final class MozcDownloadedEngineTests: XCTestCase {
    private let fm = FileManager.default
    private var downloads: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        downloads = fm.temporaryDirectory.appendingPathComponent("NRIME-downloaded-\(UUID().uuidString)")
        MozcComponents.downloadsDirectoryForTesting = downloads
    }

    override func tearDown() {
        MozcComponents.downloadsDirectoryForTesting = nil
        MozcComponents.bundledForTesting = nil
        MozcEngine.enabledForTesting = false
        try? fm.removeItem(at: downloads)
        super.tearDown()
    }

    func testAPublishedComponentIsInstalledLoadedAndConverts() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let zip = repository.appendingPathComponent("build/mozc-component/nrime-mozc.zip")
        try XCTSkipUnless(fm.fileExists(atPath: zip.path), "run Tools/mozc/package-component.sh first")

        let manifest = try Self.manifest(in: zip)
        let digest = "sha256:" + SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        let offer = MozcUpdater.Offer(abi: manifest.abi, date: manifest.date,
                                      commitPrefix: String(manifest.commit.prefix(7)),
                                      downloadURL: URL(string: "https://example.invalid/nrime-mozc.zip")!,
                                      digest: digest)
        let installed = try MozcUpdater.install(zip: zip, offer: offer, into: downloads)

        // The app's own engine counts as older, so the download is chosen.
        let bundled = try XCTUnwrap(MozcComponents.bundled)
        MozcComponents.bundledForTesting = .some(MozcComponent(
            source: .bundled, libraryURL: bundled.libraryURL, dataURL: bundled.dataURL,
            commit: "0000000000", date: "2000-01-01", version: bundled.version, directory: nil))
        MozcEngine.enabledForTesting = true
        let engine = MozcEngine.makeForTesting()

        XCTAssertTrue(engine.start())
        XCTAssertEqual(engine.active?.source, .downloaded)
        XCTAssertEqual(engine.active?.libraryURL.standardizedFileURL,
                       installed.libraryURL.standardizedFileURL, "Loaded from the download, not the app")

        var create = Mozc_Commands_Input()
        create.type = .createSession
        let session = try XCTUnwrap(engine.eval(create)?.id)
        for character in "にほんご" {
            var key = Mozc_Commands_Input()
            key.type = .sendKey
            key.id = session
            key.key.keyString = String(character)
            _ = engine.eval(key)
        }
        var space = Mozc_Commands_Input()
        space.type = .sendKey
        space.id = session
        space.key.specialKey = .space
        let output = try XCTUnwrap(engine.eval(space))
        let converted = output.preedit.segment.map(\.value).joined()
        let candidates = output.allCandidateWords.candidates.map(\.value)
        XCTAssertTrue(converted == "日本語" || candidates.contains("日本語"), "\(converted) \(candidates.prefix(5))")
    }

    private static func manifest(in zip: URL) throws -> MozcComponents.Manifest {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", zip.path, MozcComponents.manifestName]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        try unzip.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        unzip.waitUntilExit()
        return try JSONDecoder().decode(MozcComponents.Manifest.self, from: data)
    }
}
