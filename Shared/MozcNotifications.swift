import Foundation

/// How the settings app reaches the Mozc engine, which runs inside the input
/// method (distributed notifications, delivered on the input method's main queue).
enum MozcNotifications {
    /// user_dictionary.db was rewritten — reload it.
    static let userDictionaryChanged = Notification.Name("com.nrime.inputmethod.mozc.userDictionaryChanged")
    /// Forget learned conversions and predictions.
    static let clearLearning = Notification.Name("com.nrime.inputmethod.mozc.clearLearning")
    /// Look for a newer Mozc now instead of at the daily check.
    static let checkForUpdate = Notification.Name("com.nrime.inputmethod.mozc.checkForUpdate")
    /// Switch to the downloaded Mozc now: the input method saves and quits,
    /// and macOS starts it again at the next key press.
    static let applyUpdate = Notification.Name("com.nrime.inputmethod.mozc.applyUpdate")
    /// MozcStatus changed in the App Group.
    static let statusChanged = Notification.Name("com.nrime.inputmethod.mozc.statusChanged")
}
