import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "ko"

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label(String(localized: "tab.general"), systemImage: "gear")
                }
            JapaneseTab()
                .tabItem {
                    Label(String(localized: "tab.japanese"), systemImage: "character.ja")
                }
            DictionaryTab()
                .tabItem {
                    Label(String(localized: "tab.dictionary"), systemImage: "book")
                }
            PerAppTab()
                .tabItem {
                    Label(String(localized: "tab.perApp"), systemImage: "app.badge.checkmark")
                }
            AboutTab()
                .tabItem {
                    Label(String(localized: "tab.about"), systemImage: "info.circle")
                }
        }
        .padding()
        .environment(\.locale, Locale(identifier: appLanguage))
    }
}
