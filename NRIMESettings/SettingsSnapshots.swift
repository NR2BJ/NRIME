#if DEBUG
import AppKit
import SwiftUI

/// `NRIMESettings --render-snapshots <dir>`: draw each tab offscreen into PNG
/// files and quit. Lets a layout change be checked without granting screen
/// recording to anything. Debug builds only.
enum SettingsSnapshots {
    static func renderIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--render-snapshots"),
              flag + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pages: [(String, AnyView, CGFloat)] = [
            ("general", AnyView(GeneralTab()), 1500),
            ("japanese", AnyView(JapaneseTab()), 1150),
            ("japanese-dictionary", AnyView(JapaneseTab(startOnDictionary: true)), 520),
        ]
        for (name, view, height) in pages {
            render(view, height: height, to: directory.appendingPathComponent("\(name).png"))
        }
        NSApp.terminate(nil)
        return true
    }

    private static func render(_ view: AnyView, height: CGFloat, to url: URL) {
        let size = NSSize(width: 560, height: height)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).padding())
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
