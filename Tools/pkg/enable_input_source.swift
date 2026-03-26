import Carbon

let bundleID = "com.nrime.inputmethod.app"
let conditions = [kTISPropertyBundleID: bundleID as CFString] as CFDictionary
if let sources = TISCreateInputSourceList(conditions, true)?.takeRetainedValue() as? [TISInputSource] {
    for source in sources {
        TISEnableInputSource(source)
    }
}
