import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            JapaneseTab()
                .tabItem {
                    Label("Japanese", systemImage: "character.ja")
                }
            DictionaryTab()
                .tabItem {
                    Label("Dictionary", systemImage: "book")
                }
            PerAppTab()
                .tabItem {
                    Label("Per-App", systemImage: "app.badge.checkmark")
                }
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding()
    }
}
