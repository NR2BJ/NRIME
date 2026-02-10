import Carbon
import Cocoa

final class InputSourceRecovery {
    static let shared = InputSourceRecovery()

    private var consecutiveRecoveries = 0
    private let maxConsecutiveRecoveries = 5
    private var lastRecoveryTime: Date?
    private var isMonitoring = false

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged(_:)),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        NSLog("NRIME: InputSourceRecovery monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        NSLog("NRIME: InputSourceRecovery monitoring stopped")
    }

    @objc private func inputSourceChanged(_ notification: Notification) {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return
        }

        guard let sourceIDPtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            return
        }

        let currentID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String

        if !currentID.hasPrefix("com.nrime.inputmethod") {
            recoverInputSource()
        }
    }

    private func recoverInputSource() {
        let now = Date()

        if let lastTime = lastRecoveryTime, now.timeIntervalSince(lastTime) < 2.0 {
            consecutiveRecoveries += 1
        } else {
            consecutiveRecoveries = 0
        }

        guard consecutiveRecoveries < maxConsecutiveRecoveries else {
            NSLog("NRIME: InputSourceRecovery halted — too many consecutive recoveries (\(consecutiveRecoveries))")
            return
        }

        lastRecoveryTime = now

        let conditions = [
            kTISPropertyBundleID: "com.nrime.inputmethod.app"
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(conditions, false)?.takeRetainedValue() as? [TISInputSource],
              let nrimeSource = sources.first else {
            NSLog("NRIME: InputSourceRecovery could not find NRIME input source")
            return
        }

        let status = TISSelectInputSource(nrimeSource)
        if status == noErr {
            NSLog("NRIME: Input source recovered successfully")
        } else {
            NSLog("NRIME: Input source recovery failed with status: \(status)")
        }
    }
}
