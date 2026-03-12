import AppKit
import SwiftUI

@main
struct NRIMERestoreHelperApp: App {
    @NSApplicationDelegateAdaptor(RestoreHelperAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class RestoreHelperAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = LoginRestoreController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
