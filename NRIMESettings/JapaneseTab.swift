import SwiftUI

struct JapaneseTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Conversion Keys") {
                Text("Keys for converting hiragana to other character types during input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                JapaneseKeyRow(
                    title: "Hiragana",
                    description: "ひらがな",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.hiraganaKeyCode },
                        set: { store.japaneseKeyConfig.hiraganaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: "Full-width Katakana",
                    description: "全角カタカナ",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.fullKatakanaKeyCode },
                        set: { store.japaneseKeyConfig.fullKatakanaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: "Half-width Katakana",
                    description: "半角カタカナ",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.halfKatakanaKeyCode },
                        set: { store.japaneseKeyConfig.halfKatakanaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: "Full-width Romaji",
                    description: "全角ローマ字",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.fullRomajiKeyCode },
                        set: { store.japaneseKeyConfig.fullRomajiKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: "Half-width Romaji",
                    description: "半角ローマ字",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.halfRomajiKeyCode },
                        set: { store.japaneseKeyConfig.halfRomajiKeyCode = $0 }
                    )
                )
            }

            Section("Key Behavior") {
                Picker("Caps Lock Action", selection: Binding(
                    get: { store.japaneseKeyConfig.capsLockAction },
                    set: { store.japaneseKeyConfig.capsLockAction = $0 }
                )) {
                    Text("Caps Lock (Default)").tag(CapsLockAction.capsLock)
                    Text("Convert to Katakana").tag(CapsLockAction.katakana)
                    Text("Convert to Romaji").tag(CapsLockAction.romaji)
                }

                Picker("Shift Key Action", selection: Binding(
                    get: { store.japaneseKeyConfig.shiftKeyAction },
                    set: { store.japaneseKeyConfig.shiftKeyAction = $0 }
                )) {
                    Text("None (Default)").tag(ShiftKeyAction.none)
                    Text("Input Katakana").tag(ShiftKeyAction.katakana)
                    Text("Input Romaji").tag(ShiftKeyAction.romaji)
                }
            }

            Section("Space") {
                Picker("Space Width", selection: Binding(
                    get: { store.japaneseKeyConfig.fullWidthSpace },
                    set: { store.japaneseKeyConfig.fullWidthSpace = $0 }
                )) {
                    Text("Half-width (U+0020)").tag(false)
                    Text("Full-width (U+3000)").tag(true)
                }
                Text("Applies when not composing. During composition, Space triggers conversion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Punctuation & Symbols") {
                Picker("Punctuation Style", selection: Binding(
                    get: { store.japaneseKeyConfig.punctuationStyle },
                    set: { store.japaneseKeyConfig.punctuationStyle = $0 }
                )) {
                    Text("Japanese  。、").tag(PunctuationStyle.japanese)
                    Text("Western  ．，").tag(PunctuationStyle.fullWidthWestern)
                }

                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.slashToNakaguro },
                    set: { store.japaneseKeyConfig.slashToNakaguro = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/ key → ・ (Nakaguro)")
                        Text("Slash produces middle dot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.yenKeyToYen },
                    set: { store.japaneseKeyConfig.yenKeyToYen = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\\ key → ¥ (Yen Sign)")
                        Text("Backslash produces yen sign")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Conversion Shortcuts") {
                VStack(alignment: .leading, spacing: 8) {
                    KeyboardHintRow(keys: "Space / ↓", description: "Start conversion")
                    KeyboardHintRow(keys: "← / →", description: "Move between segments")
                    KeyboardHintRow(keys: "Shift + ← / →", description: "Resize segment")
                    KeyboardHintRow(keys: "↑ / ↓", description: "Navigate candidates")
                    KeyboardHintRow(keys: "Enter", description: "Confirm conversion")
                    KeyboardHintRow(keys: "Escape", description: "Cancel conversion")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Japanese Key Row

private struct JapaneseKeyRow: View {
    let title: String
    let description: String
    @Binding var keyCode: UInt16?
    @State private var isRecording = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRecording {
                Text("Press a key...")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let kc = keyCode {
                Text(keyCodeName(kc))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            if isRecording {
                Button("Cancel") {
                    isRecording = false
                }
                .buttonStyle(.borderless)
            } else {
                Button("Record") {
                    isRecording = true
                }
                .buttonStyle(.borderless)

                if keyCode != nil {
                    Button("Clear") {
                        keyCode = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .overlay {
            if isRecording {
                SingleKeyRecorderView { recorded in
                    keyCode = recorded
                    isRecording = false
                }
                .frame(width: 0, height: 0)
            }
        }
    }
}

// MARK: - Single Key Recorder

private struct SingleKeyRecorderView: NSViewRepresentable {
    var onRecord: (UInt16) -> Void

    func makeNSView(context: Context) -> SingleKeyRecorderNSView {
        let view = SingleKeyRecorderNSView()
        view.onRecord = onRecord
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: SingleKeyRecorderNSView, context: Context) {
        nsView.onRecord = onRecord
    }
}

class SingleKeyRecorderNSView: NSView {
    var onRecord: ((UInt16) -> Void)?
    private var monitor: Any?

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.onRecord?(event.keyCode)
            self?.stopMonitoring()
            return nil
        }
    }

    private func stopMonitoring() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { stopMonitoring() }
}

// MARK: - Keyboard Hint Row

private struct KeyboardHintRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .frame(width: 140, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Key Code Name

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
