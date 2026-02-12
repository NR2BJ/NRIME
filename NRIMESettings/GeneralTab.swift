import SwiftUI

struct GeneralTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutRow(
                    title: "Toggle English",
                    shortcut: $store.toggleEnglishShortcut
                )
                ShortcutRow(
                    title: "Switch to Korean",
                    shortcut: $store.switchKoreanShortcut
                )
                ShortcutRow(
                    title: "Switch to Japanese",
                    shortcut: $store.switchJapaneseShortcut
                )
                ShortcutRow(
                    title: "Hanja Conversion",
                    shortcut: $store.hanjaConvertShortcut
                )
            }

            Section("Tap Threshold") {
                VStack(alignment: .leading, spacing: 4) {
                    let needsThreshold = store.toggleEnglishShortcut.isModifierOnlyTap
                        || store.switchKoreanShortcut.isModifierOnlyTap
                        || store.switchJapaneseShortcut.isModifierOnlyTap
                        || store.hanjaConvertShortcut.isModifierOnlyTap
                    if needsThreshold {
                        HStack {
                            Text("\(String(format: "%.2f", store.tapThreshold))s")
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                            Slider(value: $store.tapThreshold, in: 0.1...0.5, step: 0.01)
                        }
                        Text("How long a modifier key can be held before it's no longer recognized as a tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not applicable — no shortcuts use modifier-only tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Display") {
                Toggle("Show inline indicator on mode switch", isOn: $store.inlineIndicatorEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Candidate Font Size")
                        Spacer()
                        Text("\(Int(store.japaneseKeyConfig.candidateFontSize))pt")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { store.japaneseKeyConfig.candidateFontSize },
                                set: { store.japaneseKeyConfig.candidateFontSize = $0 }
                            ),
                            in: 12...24,
                            step: 1
                        )
                        .frame(width: 150)
                    }
                    Text("Adjusts the text size in the candidate panel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: ShortcutConfig
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isRecording {
                Text("Press keys...")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(shortcut.label)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button(isRecording ? "Cancel" : "Record") {
                isRecording.toggle()
            }
            .buttonStyle(.borderless)
        }
        .overlay {
            if isRecording {
                KeyRecorderView { config in
                    shortcut = config
                    isRecording = false
                }
                .frame(width: 0, height: 0)
            }
        }
    }
}

// MARK: - Key Recorder (NSView bridge)

struct KeyRecorderView: NSViewRepresentable {
    var onRecord: (ShortcutConfig) -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecord = onRecord
        // Become first responder to capture keys
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onRecord = onRecord
    }
}

class KeyRecorderNSView: NSView {
    var onRecord: ((ShortcutConfig) -> Void)?

    // Track which physical modifier key is currently held
    private var heldModifierKeyCode: UInt16?
    // Delayed modifier-only tap (cancelled if keyDown arrives first)
    private var modifierTapWorkItem: DispatchWorkItem?
    // Event monitors
    private var keyDownMonitor: Any?
    private var flagsMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        stopMonitoring()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil // consume the event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event // pass through so system can track flags
        }
    }

    private func stopMonitoring() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        modifierTapWorkItem?.cancel()
        modifierTapWorkItem = nil
    }

    deinit {
        stopMonitoring()
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Cancel pending modifier-only tap — this is a combo
        modifierTapWorkItem?.cancel()
        modifierTapWorkItem = nil

        let config = buildConfig(from: event)
        onRecord?(config)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode

        // CapsLock: record immediately (no press/release distinction)
        if keyCode == 0x39 {
            modifierTapWorkItem?.cancel()
            modifierTapWorkItem = nil
            let config = ShortcutConfig(
                keyCode: keyCode,
                modifierKeyCode: keyCode,
                modifiers: 0,
                isModifierOnlyTap: true,
                label: "Caps Lock"
            )
            onRecord?(config)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        let ctrl = event.modifierFlags.contains(.control)
        let option = event.modifierFlags.contains(.option)
        let cmd = event.modifierFlags.contains(.command)
        let anyModifier = shift || ctrl || option || cmd

        if anyModifier {
            // A modifier key went down — remember its keyCode
            modifierTapWorkItem?.cancel()
            modifierTapWorkItem = nil
            if isModifierKeyCode(keyCode) {
                heldModifierKeyCode = keyCode
            }
        } else {
            // All modifiers released — schedule modifier-only tap after brief delay
            // to allow a keyDown event to arrive first (for modifier+key combos)
            let modKeyCode = heldModifierKeyCode ?? keyCode
            heldModifierKeyCode = nil

            let label = modifierKeyLabel(for: modKeyCode)
            guard !label.isEmpty else { return }

            let config = ShortcutConfig(
                keyCode: modKeyCode,
                modifierKeyCode: modKeyCode,
                modifiers: 0,
                isModifierOnlyTap: true,
                label: label
            )

            let workItem = DispatchWorkItem { [weak self] in
                self?.onRecord?(config)
            }
            modifierTapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    private func buildConfig(from event: NSEvent) -> ShortcutConfig {
        var parts: [String] = []
        let flags = event.modifierFlags
        let raw = flags.rawValue

        // Determine the modifier keyCode (which physical modifier key is held)
        var modKeyCode: UInt16 = heldModifierKeyCode ?? 0

        if flags.contains(.control) {
            let isRight = (raw & 0x2000) != 0
            parts.append(isRight ? "Right Ctrl" : "Ctrl")
            if modKeyCode == 0 { modKeyCode = isRight ? 0x3E : 0x3B }
        }
        if flags.contains(.option) {
            let isRight = (raw & 0x40) != 0
            parts.append(isRight ? "Right Option" : "Option")
            if modKeyCode == 0 { modKeyCode = isRight ? 0x3D : 0x3A }
        }
        if flags.contains(.shift) {
            let isRight = (raw & 0x04) != 0
            parts.append(isRight ? "Right Shift" : "Shift")
            if modKeyCode == 0 { modKeyCode = isRight ? 0x3C : 0x38 }
        }
        if flags.contains(.command) {
            let isRight = (raw & 0x10) != 0
            parts.append(isRight ? "Right Cmd" : "Cmd")
            if modKeyCode == 0 { modKeyCode = isRight ? 0x36 : 0x37 }
        }

        let keyName = keyCodeName(event.keyCode)
        parts.append(keyName)

        return ShortcutConfig(
            keyCode: event.keyCode,
            modifierKeyCode: modKeyCode,
            modifiers: UInt(flags.rawValue),
            isModifierOnlyTap: false,
            label: parts.joined(separator: " + ")
        )
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x38, 0x3C, 0x3B, 0x3E, 0x3A, 0x3D, 0x37, 0x36, 0x39:
            return true
        default:
            return false
        }
    }

    private func modifierKeyLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0x3C: return "Right Shift"
        case 0x38: return "Left Shift"
        case 0x3E: return "Right Ctrl"
        case 0x3B: return "Left Ctrl"
        case 0x3D: return "Right Option"
        case 0x3A: return "Left Option"
        case 0x36: return "Right Cmd"
        case 0x37: return "Left Cmd"
        case 0x39: return "Caps Lock"
        default: return ""
        }
    }

    private func keyCodeName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8",
            0x19: "9", 0x1D: "0", 0x18: "=", 0x1B: "-", 0x1E: "]",
            0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
            0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x20: "U",
            0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K",
            0x1F: "O", 0x30: "Tab", 0x31: "Space", 0x32: "`",
            0x33: "Delete", 0x24: "Return", 0x35: "Esc",
            0x39: "Caps Lock",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x69: "F13", 0x6B: "F14", 0x71: "F15",
            0x7B: "Left", 0x7C: "Right", 0x7D: "Down", 0x7E: "Up",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
