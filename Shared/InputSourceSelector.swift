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
    /// Always present on macOS and cannot be removed, so it is a safe target
    /// when we need a plain keyboard layout.
    static let asciiFallbackSourceID = "com.apple.keylayout.ABC"

    /// Select a plain ASCII keyboard layout, preferring whichever ASCII-capable
    /// source the system considers current, and falling back to ABC.
    static func selectASCIIFallback() -> InputSourceSelectionResult {
        if let asciiSource = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
           let idPtr = TISGetInputSourceProperty(asciiSource, kTISPropertyInputSourceID) {
            let sourceID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            // The ASCII-capable source can still be us (our English mode), which
            // would defeat the purpose — only use it when it is a real layout.
            if !sourceID.hasPrefix(bundleID) {
                let status = TISSelectInputSource(asciiSource)
                if status == noErr {
                    return .success(targetSourceID: sourceID)
                }
            }
        }
        return select(sourceID: asciiFallbackSourceID)
    }

    /// Select an input source by its exact source ID, enabling it if needed.
    static func select(sourceID: String) -> InputSourceSelectionResult {
        let conditions = [kTISPropertyInputSourceID: sourceID] as CFDictionary
        guard let sources = TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else {
            return .inputSourceNotFound(targetSourceID: sourceID)
        }

        if let enabledPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
            let enabled = Unmanaged<CFBoolean>.fromOpaque(enabledPtr).takeUnretainedValue()
            if !CFBooleanGetValue(enabled) {
                let enableStatus = TISEnableInputSource(source)
                guard enableStatus == noErr else {
                    return .enableFailed(targetSourceID: sourceID, status: enableStatus)
                }
            }
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else {
            return .selectFailed(targetSourceID: sourceID, status: status)
        }
        return .success(targetSourceID: sourceID)
    }

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
