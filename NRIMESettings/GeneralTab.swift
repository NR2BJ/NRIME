import SwiftUI

struct GeneralTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var transferStatusMessage: String = ""
    @State private var transferStatusIsError = false

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
                    Toggle("Prevent switching to ABC", isOn: $store.preventABCSwitch)
                    Text("Automatically switch back to NRIME when another input source is selected, keep trying during the first ~15 seconds after login or wake, and rely on NRIME's internal EN/KO/JA shortcuts afterward so system input-source switching is rarely needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            Section("Developer") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Enable Developer Mode", isOn: $store.developerModeEnabled)
                    Text("Writes local-only diagnostic logs for lifecycle and input-source events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Typed text is not recorded automatically, and nothing is uploaded unless the user shares the file manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Open Log") {
                            DeveloperLogTools.openLog()
                        }
                        Button("Reveal in Finder") {
                            DeveloperLogTools.revealLog()
                        }
                        Button("Clear Log") {
                            DeveloperLogTools.clearLog()
                        }
                    }
                    Text(verbatim: DeveloperLogTools.logFilePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Backup & Restore") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Export Settings...") {
                            exportSettings()
                        }
                        Button("Import Settings...") {
                            importSettings()
                        }
                    }

                    Text("Exports shortcuts, Japanese settings, per-app mode memory, and remembered Hanja candidate priority as a JSON file.")
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
                transferStatusMessage = "Exported settings to \(url.path)"
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
                transferStatusMessage = "Imported settings from \(url.path)"
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

    // keyCodeName is defined in KeyCodeNames.swift
}
