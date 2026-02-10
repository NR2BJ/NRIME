import Foundation

enum InputMode: String, CaseIterable {
    case english = "com.nrime.inputmethod.app.en"
    case korean = "com.nrime.inputmethod.app.ko"
    case japanese = "com.nrime.inputmethod.app.ja"

    var label: String {
        switch self {
        case .english: return "EN"
        case .korean: return "한"
        case .japanese: return "あ"
        }
    }

    var iconName: String {
        switch self {
        case .english: return "icon_en"
        case .korean: return "icon_ko"
        case .japanese: return "icon_ja"
        }
    }
}
