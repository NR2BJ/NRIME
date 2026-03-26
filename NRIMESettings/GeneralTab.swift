import SwiftUI

struct GeneralTab: View {
    @ObservedObject private var lang = LocalizedBundle.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var transferStatusMessage: String = ""
    @State private var transferStatusIsError = false

    var body: some View {
        let _ = lang.revision
        Form {
            Section(L("section.shortcuts")) {
                ShortcutRow(
                    title: L("shortcut.toggleEnglish"),
                    shortcut: $store.toggleEnglishShortcut
                )
                ShortcutRow(
                    title: L("shortcut.toggleNonEnglish"),
                    shortcut: $store.toggleNonEnglishShortcut
                )
                ShortcutRow(
                    title: L("shortcut.switchKorean"),
                    shortcut: $store.switchKoreanShortcut
                )
                ShortcutRow(
                    title: L("shortcut.switchJapanese"),
                    shortcut: $store.switchJapaneseShortcut
                )
                ShortcutRow(
                    title: L("shortcut.hanjaConversion"),
                    shortcut: $store.hanjaConvertShortcut
                )
            }

            Section(L("section.tapThreshold")) {
                VStack(alignment: .leading, spacing: 4) {
                    let needsThreshold = store.toggleEnglishShortcut.isModifierOnlyTap
                        || store.toggleNonEnglishShortcut.isModifierOnlyTap
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
                        Text(L("tapThreshold.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("tapThreshold.notApplicable"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("section.shiftDoubleTap")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(String(format: "%.2f", store.doubleTapWindow))s")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                        Slider(value: $store.doubleTapWindow, in: 0.15...0.6, step: 0.05)
                    }
                    Text(L("shiftDoubleTap.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("section.shiftEnterDelay")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(Int(store.shiftEnterDelay * 1000))ms")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                        Slider(value: $store.shiftEnterDelay, in: 0.005...0.05, step: 0.005)
                    }
                    Text(L("shiftEnterDelay.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("section.display")) {
                Toggle(L("display.inlineIndicator"), isOn: $store.inlineIndicatorEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("display.preventABC"), isOn: $store.preventABCSwitch)
                    Text(L("display.preventABC.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("display.candidateFontSize"))
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
                    Text(L("display.candidateFontSize.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("display.conversionTriggerKeys"))
                    Toggle(L("common.space"), isOn: Binding(
                        get: { store.japaneseKeyConfig.conversionTriggerSpace },
                        set: { store.japaneseKeyConfig.conversionTriggerSpace = $0 }
                    ))
                    Toggle(L("common.tab"), isOn: Binding(
                        get: { store.japaneseKeyConfig.conversionTriggerTab },
                        set: { store.japaneseKeyConfig.conversionTriggerTab = $0 }
                    ))
                    Toggle(L("common.downArrow"), isOn: Binding(
                        get: { store.japaneseKeyConfig.conversionTriggerDownArrow },
                        set: { store.japaneseKeyConfig.conversionTriggerDownArrow = $0 }
                    ))
                    Text(L("display.conversionTriggerKeys.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("section.developer")) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("developer.enableMode"), isOn: $store.developerModeEnabled)
                    Text(L("developer.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L("developer.privacyNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button(L("developer.openLog")) {
                            DeveloperLogTools.openLog()
                        }
                        Button(L("developer.revealInFinder")) {
                            DeveloperLogTools.revealLog()
                        }
                        Button(L("developer.clearLog")) {
                            DeveloperLogTools.clearLog()
                        }
                    }
                    Text(verbatim: DeveloperLogTools.logFilePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section(L("section.backupRestore")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button(L("backup.export")) {
                            exportSettings()
                        }
                        Button(L("backup.import")) {
                            importSettings()
                        }
                    }

                    Text(L("backup.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !transferStatusMessage.isEmpty {
                        Text(transferStatusMessage)
                            .font(.caption)
                            .foregroundStyle(transferStatusIsError ? .red : .secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportSettings() {
        do {
            if let url = try store.exportSettingsInteractively() {
                transferStatusMessage = String(format: L("backup.exported"), url.path)
                transferStatusIsError = false
            }
        } catch {
            transferStatusMessage = error.localizedDescription
            transferStatusIsError = true
        }
    }

    private func importSettings() {
        do {
            if let url = try store.importSettingsInteractively() {
                transferStatusMessage = String(format: L("backup.imported"), url.path)
                transferStatusIsError = false
            }
        } catch {
            transferStatusMessage = error.localizedDescription
            transferStatusIsError = true
        }
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
                Text(L("shortcutRow.pressKeys"))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(shortcut.disabled ? L("shortcutRow.none") : shortcut.label)
                    .foregroundStyle(shortcut.disabled ? .secondary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button(isRecording ? L("shortcutRow.cancel") : L("shortcutRow.record")) {
                isRecording.toggle()
            }
            .buttonStyle(.borderless)
            if !isRecording && !shortcut.disabled {
                Button(L("shortcutRow.clear")) {
                    var cleared = shortcut
                    cleared.disabled = true
                    cleared.label = "None"
                    shortcut = cleared
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if isRecording {
                KeyRecorderView { config in
                    var newConfig = config
                    newConfig.disabled = false
                    shortcut = newConfig
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

    // keyCodeName is defined in KeyCodeNames.swift
}
