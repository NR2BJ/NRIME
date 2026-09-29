import Foundation

/// How the settings app reaches the Mozc engine, which runs inside the input
/// method (distributed notifications, delivered on the input method's main queue).
enum MozcNotifications {
    /// user_dictionary.db was rewritten — reload it.
    static let userDictionaryChanged = Notification.Name("com.nrime.inputmethod.mozc.userDictionaryChanged")
    /// Forget learned conversions and predictions.
    static let clearLearning = Notification.Name("com.nrime.inputmethod.mozc.clearLearning")
}
