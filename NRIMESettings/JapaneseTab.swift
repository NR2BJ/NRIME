import SwiftUI

struct JapaneseTab: View {
    @ObservedObject private var lang = LocalizedBundle.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var showingClearConfirmation = false
    @State private var historyCleared = false

    var body: some View {
        let _ = lang.revision
        Form {
            Section(L("section.conversionKeys")) {
                Text(L("conversionKeys.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                JapaneseKeyRow(
                    title: L("japanese.hiragana"),
                    description: "\u{3072}\u{3089}\u{304C}\u{306A}",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.hiraganaKeyCode },
                        set: { store.japaneseKeyConfig.hiraganaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: L("japanese.fullKatakana"),
                    description: "\u{5168}\u{89D2}\u{30AB}\u{30BF}\u{30AB}\u{30CA}",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.fullKatakanaKeyCode },
                        set: { store.japaneseKeyConfig.fullKatakanaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: L("japanese.halfKatakana"),
                    description: "\u{534A}\u{89D2}\u{30AB}\u{30BF}\u{30AB}\u{30CA}",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.halfKatakanaKeyCode },
                        set: { store.japaneseKeyConfig.halfKatakanaKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: L("japanese.fullRomaji"),
                    description: "\u{5168}\u{89D2}\u{30ED}\u{30FC}\u{30DE}\u{5B57}",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.fullRomajiKeyCode },
                        set: { store.japaneseKeyConfig.fullRomajiKeyCode = $0 }
                    )
                )
                JapaneseKeyRow(
                    title: L("japanese.halfRomaji"),
                    description: "\u{534A}\u{89D2}\u{30ED}\u{30FC}\u{30DE}\u{5B57}",
                    keyCode: Binding(
                        get: { store.japaneseKeyConfig.halfRomajiKeyCode },
                        set: { store.japaneseKeyConfig.halfRomajiKeyCode = $0 }
                    )
                )
            }

            Section(L("section.keyBehavior")) {
                Picker(L("keyBehavior.capsLockAction"), selection: Binding(
                    get: { store.japaneseKeyConfig.capsLockAction },
                    set: { store.japaneseKeyConfig.capsLockAction = $0 }
                )) {
                    Text(L("capsLock.default")).tag(CapsLockAction.capsLock)
                    Text(L("capsLock.katakana")).tag(CapsLockAction.katakana)
                    Text(L("capsLock.romaji")).tag(CapsLockAction.romaji)
                }

                Picker(L("keyBehavior.shiftKeyAction"), selection: Binding(
                    get: { store.japaneseKeyConfig.shiftKeyAction },
                    set: { store.japaneseKeyConfig.shiftKeyAction = $0 }
                )) {
                    Text(L("shiftKey.none")).tag(ShiftKeyAction.none)
                    Text(L("shiftKey.katakana")).tag(ShiftKeyAction.katakana)
                    Text(L("shiftKey.romaji")).tag(ShiftKeyAction.romaji)
                }
            }

            Section(L("section.space")) {
                Picker(L("space.width"), selection: Binding(
                    get: { store.japaneseKeyConfig.fullWidthSpace },
                    set: { store.japaneseKeyConfig.fullWidthSpace = $0 }
                )) {
                    Text(L("space.halfWidth")).tag(false)
                    Text(L("space.fullWidth")).tag(true)
                }
                Text(L("space.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("section.punctuation")) {
                Picker(L("punctuation.style"), selection: Binding(
                    get: { store.japaneseKeyConfig.punctuationStyle },
                    set: { store.japaneseKeyConfig.punctuationStyle = $0 }
                )) {
                    Text(L("punctuation.japanese")).tag(PunctuationStyle.japanese)
                    Text(L("punctuation.fullWidthWestern")).tag(PunctuationStyle.fullWidthWestern)
                    Text(L("punctuation.halfWidthWestern")).tag(PunctuationStyle.halfWidthWestern)
                }

                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.slashToNakaguro },
                    set: { store.japaneseKeyConfig.slashToNakaguro = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("punctuation.slashToNakaguro"))
                        Text(L("punctuation.slashDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.yenKeyToYen },
                    set: { store.japaneseKeyConfig.yenKeyToYen = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("punctuation.yenKey"))
                        Text(L("punctuation.yenDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("section.inputFeatures")) {
                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.liveConversion },
                    set: { store.japaneseKeyConfig.liveConversion = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("inputFeatures.liveConversion"))
                        Text(L("inputFeatures.liveConversion.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { store.japaneseKeyConfig.prediction },
                    set: { store.japaneseKeyConfig.prediction = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("inputFeatures.prediction"))
                        Text(L("inputFeatures.prediction.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("section.conversionHistory")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("conversionHistory.clear"))
                        Text(L("conversionHistory.clear.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("conversionHistory.clearButton")) {
                        showingClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }

            Section(L("section.conversionShortcuts")) {
                VStack(alignment: .leading, spacing: 8) {
                    KeyboardHintRow(keys: "Space / \u{2193}", description: L("convShortcut.startConversion"))
                    KeyboardHintRow(keys: "\u{2190} / \u{2192}", description: L("convShortcut.moveSegments"))
                    KeyboardHintRow(keys: "Shift + \u{2190} / \u{2192}", description: L("convShortcut.resizeSegment"))
                    KeyboardHintRow(keys: "\u{2191} / \u{2193}", description: L("convShortcut.navigateCandidates"))
                    KeyboardHintRow(keys: "Enter", description: L("convShortcut.confirmConversion"))
                    KeyboardHintRow(keys: "Escape", description: L("convShortcut.cancelConversion"))
                    KeyboardHintRow(keys: "Tab", description: L("convShortcut.selectPrediction"))
                }
            }
        }
        .formStyle(.grouped)
        .alert(L("conversionHistory.confirmTitle"), isPresented: $showingClearConfirmation) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("conversionHistory.clearButton"), role: .destructive) {
                clearMozcHistory()
            }
        } message: {
            Text(L("conversionHistory.confirmMessage"))
        }
        .alert(L("conversionHistory.clearedTitle"), isPresented: $historyCleared) {
            Button(L("common.ok")) { }
        } message: {
            Text(L("conversionHistory.clearedMessage"))
        }
    }

    private func clearMozcHistory() {
        let mozcDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozc")

        let historyFiles = ["segment.db", "boundary.db", ".history.db"]
        for file in historyFiles {
            let url = mozcDir.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: url)
        }

        // Kill mozc_server so it restarts with clean state
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["mozc_server"]
        try? task.run()

        historyCleared = true
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
                Text(L("keyRecorder.pressKey"))
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
                Text(L("keyRecorder.none"))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            if isRecording {
                Button(L("keyRecorder.cancel")) {
                    isRecording = false
                }
                .buttonStyle(.borderless)
            } else {
                Button(L("keyRecorder.record")) {
                    isRecording = true
                }
                .buttonStyle(.borderless)

                if keyCode != nil {
                    Button(L("keyRecorder.clear")) {
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

// keyCodeName is defined in KeyCodeNames.swift
