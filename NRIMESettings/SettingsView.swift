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
        .id(appLanguage)  // Force full re-render on language change
        .environment(\.locale, Locale(identifier: appLanguage))
        .onChange(of: appLanguage) { _ in
            LocalizedBundle.shared.update(language: appLanguage)
        }
        .onAppear {
            LocalizedBundle.shared.update(language: appLanguage)
        }
    }
}

// MARK: - Localization Helper

/// Looks up a key from the lproj bundle matching the user's selected language.
func L(_ key: String) -> String {
    LocalizedBundle.shared.string(for: key)
}

class LocalizedBundle: ObservableObject {
    static let shared = LocalizedBundle()
    private var bundle: Bundle = .main
    /// Incremented on language change to trigger SwiftUI re-renders.
    @Published var revision: Int = 0

    init() {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
        update(language: lang)
    }

    func update(language: String) {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            bundle = lprojBundle
        } else {
            bundle = .main
        }
        revision += 1
    }

    func string(for key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
