import XCTest
@testable import NRIME

/// Runs against the test-only log directory (DeveloperLogLocation under XCTest)
/// and the isolated settings domain, never the user's real log or settings.
final class DeveloperLoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Settings.shared.developerModeEnabled = true
        DeveloperLogger.shared.maxLogBytesForTesting = 512 * 1024
        try? FileManager.default.removeItem(at: DeveloperLogLocation.directoryURL())
    }

    override func tearDown() {
        DeveloperLogger.shared.maxLogBytesForTesting = nil
        Settings.shared.developerModeEnabled = false
        try? FileManager.default.removeItem(at: DeveloperLogLocation.directoryURL())
        super.tearDown()
    }

    func testLogStaysOutOfTheUsersLogDirectory() {
        XCTAssertFalse(DeveloperLogLocation.fileURL().path.contains("/Library/Logs/NRIME"))
    }

    func testLinesCarryTheUptimeOfTheCallNotOfTheWrite() throws {
        let before = ProcessInfo.processInfo.systemUptime
        DeveloperLogger.shared.log("Test", "marker")
        let after = ProcessInfo.processInfo.systemUptime
        DeveloperLogger.shared.drainForTesting()

        let text = try String(contentsOf: DeveloperLogLocation.fileURL(), encoding: .utf8)
        let line = try XCTUnwrap(text.split(separator: "\n").first { $0.contains("marker") })
        let upField = try XCTUnwrap(line.split(separator: " ").first { $0.hasPrefix("up=") })
        let up = try XCTUnwrap(Double(upField.dropFirst(3)))
        XCTAssertGreaterThanOrEqual(up, before - 0.001)
        XCTAssertLessThanOrEqual(up, after + 0.001)
    }

    func testRotationKeepsThePreviousGeneration() throws {
        let filler = String(repeating: "x", count: 1000)
        for _ in 0..<600 {
            DeveloperLogger.shared.log("Test", filler)
        }
        DeveloperLogger.shared.log("Test", "after-rotation")
        DeveloperLogger.shared.drainForTesting()

        let previous = DeveloperLogLocation.directoryURL().appendingPathComponent("developer.log.1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
        let current = try String(contentsOf: DeveloperLogLocation.fileURL(), encoding: .utf8)
        XCTAssertTrue(current.contains("after-rotation"))
        XCTAssertTrue(current.contains("# Rotated at"))
    }

    func testClearingRemovesTheRotatedGenerationToo() throws {
        let filler = String(repeating: "x", count: 1000)
        for _ in 0..<600 {
            DeveloperLogger.shared.log("Test", filler)
        }
        DeveloperLogger.shared.drainForTesting()
        XCTAssertTrue(FileManager.default.fileExists(atPath: DeveloperLogLocation.previousFileURL().path))

        try DeveloperLogger.clearLog()
        XCTAssertFalse(FileManager.default.fileExists(atPath: DeveloperLogLocation.previousFileURL().path))
        let current = try String(contentsOf: DeveloperLogLocation.fileURL(), encoding: .utf8)
        XCTAssertFalse(current.contains("xxxx"))
    }
}
