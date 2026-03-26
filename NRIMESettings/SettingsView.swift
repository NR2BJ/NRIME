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
    private var currentLanguage: String = ""
    /// Incremented on language change to trigger SwiftUI re-renders.
    @Published var revision: Int = 0

    init() {
        syncWithUserDefaults()
    }

    func update(language: String) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            bundle = lprojBundle
        } else {
            bundle = .main
        }
        revision += 1
    }

    /// Ensure bundle matches UserDefaults (called from L() on every lookup)
    private func syncWithUserDefaults() {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
        if lang != currentLanguage {
            update(language: lang)
        }
    }

    func string(for key: String) -> String {
        syncWithUserDefaults()
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
