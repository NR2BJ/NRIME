import Carbon
import Foundation

enum InputSourceSelectionResult {
    case success(targetSourceID: String)
    case inputSourceNotFound(targetSourceID: String)
    case enableFailed(targetSourceID: String, status: OSStatus)
    case selectFailed(targetSourceID: String, status: OSStatus)
}

enum InputSourceSelector {
    static let bundleID = "com.nrime.inputmethod.app"
    static let visibleInputSourceID = "com.nrime.inputmethod.app.en"

    static func currentInputSourceID() -> String? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let sourceIDPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
    }

    static func currentSourceIsNonNRIME() -> Bool {
        guard let currentID = currentInputSourceID() else { return false }
        return !currentID.hasPrefix(bundleID)
    }

    static func selectVisibleNRIME() -> InputSourceSelectionResult {
        let targetSourceID = visibleInputSourceID
        let conditions = [
            kTISPropertyInputSourceID: targetSourceID
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource],
              let nrimeSource = sources.first else {
            return .inputSourceNotFound(targetSourceID: targetSourceID)
        }

        if let enabledPtr = TISGetInputSourceProperty(nrimeSource, kTISPropertyInputSourceIsEnabled) {
            let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            if !CFBooleanGetValue(enabled) {
                let enableStatus = TISEnableInputSource(nrimeSource)
                guard enableStatus == noErr else {
                    return .enableFailed(targetSourceID: targetSourceID, status: enableStatus)
                }
            }
        }

        let status = TISSelectInputSource(nrimeSource)
        guard status == noErr else {
            return .selectFailed(targetSourceID: targetSourceID, status: status)
        }

        return .success(targetSourceID: targetSourceID)
    }
}
