import XCTest
@testable import NRIME

/// Content-based Chromium/Electron detection. Name-only matching broke when the
/// ChatGPT app renamed "Electron Framework" to "Codex Framework" — these tests
/// pin every signal the detector accepts, using synthetic bundles on disk.
final class ChromiumDetectorTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChromiumDetectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(_ name: String, files: [String]) throws -> String {
        let bundle = root.appendingPathComponent(name)
        for relative in files {
            let url = bundle.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return bundle.path
    }

    func testDetectsAppAsar() throws {
        let path = try makeBundle("Asar.app", files: ["Contents/Resources/app.asar"])
        XCTAssertTrue(ChromiumDetector.isChromiumBundle(atPath: path))
    }

    func testDetectsUnpackedElectronApp() throws {
        let path = try makeBundle("Unpacked.app",
                                  files: ["Contents/Resources/app/package.json"])
        XCTAssertTrue(ChromiumDetector.isChromiumBundle(atPath: path))
    }

    func testDetectsCanonicalElectronFrameworkName() throws {
        let path = try makeBundle("Electron.app", files: [
            "Contents/Frameworks/Electron Framework.framework/Versions/A/Electron Framework",
        ])
        XCTAssertTrue(ChromiumDetector.isChromiumBundle(atPath: path))
    }

    func testDetectsRenamedFrameworkViaV8Snapshot() throws {
        // The ChatGPT/Codex case: framework renamed, but V8 snapshot remains.
        let path = try makeBundle("Renamed.app", files: [
            "Contents/Frameworks/Codex Framework.framework/Versions/A/Resources/v8_context_snapshot.arm64.bin",
        ])
        XCTAssertTrue(ChromiumDetector.isChromiumBundle(atPath: path))
    }

    func testNativeAppIsNotChromium() throws {
        let path = try makeBundle("Native.app", files: [
            "Contents/MacOS/Native",
            "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
            "Contents/Resources/AppIcon.icns",
        ])
        XCTAssertFalse(ChromiumDetector.isChromiumBundle(atPath: path))
    }

    func testMissingFrameworksDirectoryIsNotChromium() throws {
        let path = try makeBundle("Bare.app", files: ["Contents/MacOS/Bare"])
        XCTAssertFalse(ChromiumDetector.isChromiumBundle(atPath: path))
    }
}
