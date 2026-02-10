import SwiftUI

@main
struct NRIMESettingsApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
                .frame(minWidth: 520, minHeight: 440)
        }
        .windowResizability(.contentSize)
    }
}
