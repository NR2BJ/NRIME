import Cocoa

/// Utility for re-posting key events to the frontmost application
/// after committing composing text.
///
/// Problem: When an IMKit input method calls `client.insertText()` inside `handle()`
/// and returns `false`, the original key event is not reliably forwarded to the host app
/// (especially in Electron-based apps like Slack, Discord, VS Code, Claude for Desktop).
///
/// CGEvent-based approaches all fail with Electron:
/// - `CGEvent.post(tap: .cghidEventTap)` — goes through IMKit, event swallowed
/// - `CGEvent.post(tap: .cgAnnotatedSessionEventTap)` — bypasses IMKit but Electron ignores
/// - `CGEventPostToPSN` — direct to process, but Electron still ignores
///
/// Solution: Use macOS System Events via AppleScript to send keystrokes.
/// System Events uses the accessibility layer which ALL apps receive, including Electron.
enum KeyEventReposter {

    /// Sentinel value stored in `eventSourceUserData` to mark re-posted events.
    /// Used by controller to detect and pass through reposted events.
    static let repostTag: Int64 = 0x4E52494D45  // "NRIME" in ASCII-ish hex

    /// Re-post a key event via System Events AppleScript.
    /// Runs asynchronously on a background queue to avoid blocking the main thread.
    /// - Parameters:
    ///   - keyCode: The virtual key code to re-post.
    ///   - modifiers: The modifier flags from the original NSEvent.
    static func repost(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Build AppleScript modifier list
        var modParts: [String] = []
        if modifiers.contains(.shift)   { modParts.append("shift down") }
        if modifiers.contains(.command) { modParts.append("command down") }
        if modifiers.contains(.option)  { modParts.append("option down") }
        if modifiers.contains(.control) { modParts.append("control down") }

        let modStr: String
        if modParts.isEmpty {
            modStr = ""
        } else if modParts.count == 1 {
            modStr = " using \(modParts[0])"
        } else {
            modStr = " using {\(modParts.joined(separator: ", "))}"
        }

        let script = "tell application \"System Events\" to key code \(keyCode)\(modStr)"

        DeveloperLogger.shared.log("KeyEventReposter", "sending via System Events", metadata: [
            "keyCode": String(format: "0x%02X", keyCode),
            "script": script
        ])

        DispatchQueue.global(qos: .userInteractive).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error = error {
                DeveloperLogger.shared.log("KeyEventReposter", "AppleScript FAILED", metadata: [
                    "error": error.description
                ])
            }
        }
    }
}
