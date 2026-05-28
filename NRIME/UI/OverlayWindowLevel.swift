import Cocoa

enum OverlayWindowLevel {
    private static let knownHighPriorityBundleIDs: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
    ]

    static var frontmostOverlayLevel: NSWindow.Level {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostLayers = frontmostApp.map { windowLayers(forOwnerPID: $0.processIdentifier) } ?? []
        let rawValue = overlayLevelRawValue(
            frontmostWindowLayers: frontmostLayers,
            frontmostBundleID: frontmostApp?.bundleIdentifier
        )
        return NSWindow.Level(rawValue: rawValue)
    }

    static func overlayLevelRawValue(
        frontmostWindowLayers: [Int],
        frontmostBundleID: String? = nil,
        base: Int = Int(CGWindowLevelForKey(.floatingWindow)),
        maximum: Int = Int(CGWindowLevelForKey(.screenSaverWindow)) - 1
    ) -> Int {
        let minimumForKnownHighPriorityApp = knownHighPriorityBundleIDs.contains(frontmostBundleID ?? "")
            ? Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1
            : base
        let topLayer = frontmostWindowLayers.max() ?? 0
        let desiredLevel = topLayer >= base ? topLayer + 1 : base
        return min(max(desiredLevel, minimumForKnownHighPriorityApp), maximum)
    }

    private static func windowLayers(forOwnerPID pid: pid_t) -> [Int] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { info in
            guard intValue(info[kCGWindowOwnerPID as String]) == Int(pid),
                  (doubleValue(info[kCGWindowAlpha as String]) ?? 1) > 0,
                  let layer = intValue(info[kCGWindowLayer as String]),
                  windowHasVisibleBounds(info[kCGWindowBounds as String]) else {
                return nil
            }
            return layer
        }
    }

    private static func windowHasVisibleBounds(_ value: Any?) -> Bool {
        guard let dictionary = value as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else {
            return true
        }
        return rect.width > 1 && rect.height > 1
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}
