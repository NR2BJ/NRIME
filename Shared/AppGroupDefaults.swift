import Foundation

/// The App Group defaults every NRIME process shares — or, under XCTest, a
/// private domain that starts empty on every run.
///
/// Tests run inside a host built from this repository on the developer's own
/// Mac, so "the App Group" there is the user's live configuration. A test
/// that set the language-switch shortcuts in setUp and never restored them
/// silently replaced the user's hotkeys with the defaults: Left Shift stopped
/// switching, and Shift+Space started to. Isolating the domain here makes
/// that impossible for every test, present and future, instead of relying
/// on each one to save and restore correctly.
enum AppGroupDefaults {
    static let suiteName = "group.com.nrime.inputmethod"

    /// Domain used in place of the App Group while tests run.
    static let testingSuiteName = "test.nrime.appgroup"

    /// Whether this process is an XCTest host.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    /// Cleared once per process so leftovers from a previous run cannot leak
    /// into this one.
    private static let clearTestingDomainOnce: Void = {
        UserDefaults(suiteName: testingSuiteName)?.removePersistentDomain(forName: testingSuiteName)
    }()

    static func make() -> UserDefaults {
        if isRunningTests {
            _ = clearTestingDomainOnce
            return UserDefaults(suiteName: testingSuiteName) ?? .standard
        }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
