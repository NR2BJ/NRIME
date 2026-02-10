import Foundation

enum InputMode: String, CaseIterable {
    case english = "com.nrime.inputmethod.NRIME.en"
    case korean = "com.nrime.inputmethod.NRIME.ko"
    case japanese = "com.nrime.inputmethod.NRIME.ja"

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
