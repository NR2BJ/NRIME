import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguage: String = "ko"

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label(L("tab.general"), systemImage: "gear")
                }
            JapaneseTab()
                .tabItem {
                    Label(L("tab.japanese"), systemImage: "character.ja")
                }
            DictionaryTab()
                .tabItem {
                    Label(L("tab.dictionary"), systemImage: "book")
                }
            PerAppTab()
                .tabItem {
                    Label(L("tab.perApp"), systemImage: "app.badge.checkmark")
                }
            AboutTab()
                .tabItem {
                    Label(L("tab.about"), systemImage: "info.circle")
                }
        }
        .padding()
        .environment(\.locale, Locale(identifier: appLanguage))
        .onChange(of: appLanguage) { _ in
            // Force Bundle to use selected language for String(localized:) calls
            LocalizedBundle.shared.update(language: appLanguage)
        }
        .onAppear {
            LocalizedBundle.shared.update(language: appLanguage)
        }
    }
}

// MARK: - Localization Helper

/// Looks up a key from the lproj bundle matching the user's selected language.
/// Works for String contexts (Section titles, Button labels, etc.) where
/// SwiftUI's .environment(\.locale) doesn't reach.
func L(_ key: String) -> String {
    LocalizedBundle.shared.string(for: key)
}

class LocalizedBundle {
    static let shared = LocalizedBundle()
    private var bundle: Bundle = .main

    func update(language: String) {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            bundle = lprojBundle
        } else {
            bundle = .main
        }
    }

    func string(for key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
