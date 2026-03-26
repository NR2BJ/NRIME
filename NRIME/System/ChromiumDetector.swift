import AppKit

/// Detects whether the current frontmost app is Chromium-based (Electron, CEF, Chrome).
/// Used to apply Chromium-specific workarounds (e.g., async insertText for Shift+Enter).
enum ChromiumDetector {
    private static var cache: [String: Bool] = [:]

    /// Returns true if the frontmost application uses Chromium/Electron.
    /// Result is cached per bundle path to avoid repeated filesystem checks.
    static var isFrontmostAppChromium: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundlePath = app.bundleURL?.path else {
            return false
        }

        if let cached = cache[bundlePath] {
            return cached
        }

        let frameworksPath = bundlePath + "/Contents/Frameworks"
        let fm = FileManager.default
        let isChromium = fm.fileExists(atPath: frameworksPath + "/Electron Framework.framework") ||
                         fm.fileExists(atPath: frameworksPath + "/Chromium Embedded Framework.framework") ||
                         fm.fileExists(atPath: frameworksPath + "/Google Chrome Framework.framework")

        cache[bundlePath] = isChromium
        return isChromium
    }
}
