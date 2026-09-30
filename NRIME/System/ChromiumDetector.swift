import AppKit

/// Detects whether the current frontmost app is Chromium-based (Electron, CEF, Chrome).
/// Used to apply Chromium-specific workarounds (e.g., async insertText for Shift+Enter).
enum ChromiumDetector {
    private static var cache: [String: Bool] = [:]

#if DEBUG
    /// Test seam: forces the verdict regardless of the frontmost app.
    static var overrideForTesting: Bool?
    /// Test seam for the newline-submit quirk below.
    static var newlineQuirkOverrideForTesting: Bool?
#endif

    /// Electron apps whose editor needs Shift+Enter as a real key press after
    /// the commit, not an inserted "\n". For these the Shift+Enter workaround
    /// replays the key press instead.
    ///
    /// Claude desktop was on this list for 1.0.12-beta.7 and is not any more:
    /// with no wait its inserted "\n" lost the syllable being composed, but
    /// the replayed key lost it too on a slower Mac (Codex, same day). What
    /// both needed was the wait; with it, the inserted "\n" that worked in
    /// Claude for months is back.
    private static let newlineKeyPressBundleIDs: Set<String> = [
        // ChatGPT/Codex desktop: an inserted "\n" sends the message
        // (verified 2026-07 beta test).
        "com.openai.codex",
    ]

    /// Whether this app needs the Shift+Enter newline as a real key press.
    static func needsNewlineKeyPress(bundleID: String) -> Bool {
        newlineKeyPressBundleIDs.contains(bundleID)
    }

    /// Whether the frontmost app needs the Shift+Enter newline as a key press.
    static var frontmostAppNeedsNewlineKeyPress: Bool {
#if DEBUG
        if let forced = newlineQuirkOverrideForTesting { return forced }
#endif
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return needsNewlineKeyPress(bundleID: bundleID)
    }

    /// Returns true if the frontmost application uses Chromium/Electron.
    /// Result is cached per bundle path to avoid repeated filesystem checks.
    static var isFrontmostAppChromium: Bool {
#if DEBUG
        if let forced = overrideForTesting { return forced }
#endif
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundlePath = app.bundleURL?.path else {
            return false
        }

        if let cached = cache[bundlePath] {
            return cached
        }

        let isChromium = isChromiumBundle(atPath: bundlePath)
        cache[bundlePath] = isChromium
        return isChromium
    }

    /// Content-based detection. Framework names alone are not reliable: the
    /// ChatGPT app renamed "Electron Framework.framework" to
    /// "Codex Framework.framework", which silently broke name-only matching —
    /// Shift+Enter then took the non-Chromium path and the composing text was
    /// eaten by the renderer.
    static func isChromiumBundle(atPath bundlePath: String) -> Bool {
        let fm = FileManager.default
        let contents = bundlePath + "/Contents"

        // Electron hallmark: the bundled JS app (survives framework renames)
        if fm.fileExists(atPath: contents + "/Resources/app.asar")
            || fm.fileExists(atPath: contents + "/Resources/app/package.json") {
            return true
        }

        let frameworksPath = contents + "/Frameworks"

        // Fast path: canonical framework names
        for name in ["Electron Framework.framework",
                     "Chromium Embedded Framework.framework",
                     "Google Chrome Framework.framework"] {
            if fm.fileExists(atPath: frameworksPath + "/" + name) {
                return true
            }
        }

        // Renamed frameworks: any framework shipping a V8 context snapshot
        guard let frameworks = try? fm.contentsOfDirectory(atPath: frameworksPath) else {
            return false
        }
        for framework in frameworks where framework.hasSuffix(".framework") {
            let base = frameworksPath + "/" + framework
            for snapshot in ["/Resources/v8_context_snapshot.arm64.bin",
                             "/Resources/v8_context_snapshot.x86_64.bin",
                             "/Resources/v8_context_snapshot.bin",
                             "/Versions/A/Resources/v8_context_snapshot.arm64.bin",
                             "/Versions/A/Resources/v8_context_snapshot.x86_64.bin",
                             "/Versions/A/Resources/v8_context_snapshot.bin"] {
                if fm.fileExists(atPath: base + snapshot) {
                    return true
                }
            }
        }

        return false
    }
}
