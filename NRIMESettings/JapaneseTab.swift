import Combine
import SwiftUI

struct JapaneseTab: View {
    @ObservedObject private var lang = LocalizedBundle.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var page: Page
    @State private var showingClearConfirmation = false
    @State private var historyCleared = false
    @State private var mozcStatus: MozcStatus?

    init(startOnDictionary: Bool = false) {
        _page = State(initialValue: startOnDictionary ? .dictionary : .settings)
    }

    /// The user dictionary lives inside this tab rather than in one of its own.
    /// It is a table, which does not belong inside a Form, so it gets its own page.
    private enum Page: Hashable {
        case settings
        case dictionary
    }

    var body: some View {
        let _ = lang.revision
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text(L("japanese.page.settings")).tag(Page.settings)
                Text(L("japanese.page.dictionary")).tag(Page.dictionary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 8)

            switch page {
            case .settings:
                settingsForm
            case .dictionary:
                DictionaryTab()
            }
        }
    }

    private var settingsForm: some View {
        Form {
            Section(L("display.conversionTriggerKeys")) {
                Toggle(L("common.space"), isOn: Binding(
                    get: { store.japaneseKeyConfig.conversionTriggerSpace },
                    set: { store.japaneseKeyConfig.conversionTriggerSpace = $0 }
                ))
                Toggle(L("common.tab"), isOn: Binding(
                    get: { store.japaneseKeyConfig.conversionTriggerTab },
                    set: { store.japaneseKeyConfig.conversionTriggerTab = $0 }
                ))
                Text(L("display.conversionTriggerKeys.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("punctuation.preview"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: Self.punctuationPreview(store.japaneseKeyConfig.punctuationStyle))
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text(L("punctuation.previewNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            mozcSection

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
                    KeyboardHintRow(keys: "Space / Tab", description: L("convShortcut.startConversion"))
                    KeyboardHintRow(keys: "\u{2191} / \u{2193}", description: L("convShortcut.navigateCandidates"))
                    KeyboardHintRow(keys: "\u{2190} / \u{2192}", description: L("convShortcut.moveSegments"))
                    KeyboardHintRow(keys: "Shift + \u{2190} / \u{2192}", description: L("convShortcut.resizeSegment"))
                    KeyboardHintRow(keys: "1 \u{2013} 9", description: L("convShortcut.selectByNumber"))
                    KeyboardHintRow(keys: "Tab", description: L("convShortcut.toggleGrid"))
                    KeyboardHintRow(keys: "Enter", description: L("convShortcut.confirmConversion"))
                    KeyboardHintRow(keys: "Escape", description: L("convShortcut.cancelConversion"))
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

    /// Which Mozc the input method runs, a newer one waiting, and the update
    /// check. Mozc updates on its own, without a new NRIME (MozcUpdater); the
    /// input method publishes this in the App Group (MozcStatus).
    private var mozcSection: some View {
        Section(L("section.mozc")) {
            LabeledContent(L("mozc.version")) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: mozcVersionText)
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Text(mozcStatus?.activeSource == "downloaded"
                         ? L("mozc.source.downloaded") : L("mozc.source.bundled"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let pending = mozcStatus?.pending {
                HStack {
                    Text(String(format: L("mozc.pending"), pending.version, pending.date))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("mozc.applyNow")) {
                        DistributedNotificationCenter.default().postNotificationName(
                            MozcNotifications.applyUpdate, object: nil, userInfo: nil, deliverImmediately: true)
                    }
                    .help(L("mozc.applyNow.help"))
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("mozc.update"))
                    if let checked = mozcStatus?.checkedAt {
                        Text(String(format: L("mozc.checkedAt"),
                                    checked.formatted(date: .abbreviated, time: .shortened)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(L("mozc.checkNow")) {
                    DistributedNotificationCenter.default().postNotificationName(
                        MozcNotifications.checkForUpdate, object: nil, userInfo: nil, deliverImmediately: true)
                }
            }

            Text(L("mozc.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { mozcStatus = MozcStatus.load(from: AppGroupDefaults.make()) }
        .onReceive(DistributedNotificationCenter.default()
            .publisher(for: MozcNotifications.statusChanged)
            .receive(on: RunLoop.main)) { _ in
            mozcStatus = MozcStatus.load(from: AppGroupDefaults.make())
        }
    }

    /// "3.34.6239.101 (2026-09-28)": what the input method reports it runs,
    /// else the Mozc bundled in NRIME.app, before the input method has said.
    private var mozcVersionText: String {
        if let active = mozcStatus?.active {
            return "\(active.version) (\(active.date))"
        }
        let file = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("NRIME.app/Contents/Resources/MOZC_VERSION")
        // "<commit> <date> <version>"
        if let line = try? String(contentsOf: file, encoding: .utf8) {
            let parts = line.split(separator: " ")
            if parts.count >= 3 {
                return "\(parts[2].trimmingCharacters(in: .whitespacesAndNewlines)) (\(parts[1]))"
            }
        }
        return "—"
    }

    /// What the period, comma, brackets, tilde, ! and ? keys type in each
    /// style. Mirrors JapaneseEngine.symbolForms — keep the two in step.
    static func punctuationPreview(_ style: PunctuationStyle) -> String {
        switch style {
        case .japanese:         return "。 、 「 」 〜 ！ ？"
        case .fullWidthWestern: return "． ， ［ ］ ～ ！ ？"
        case .halfWidthWestern: return ". , [ ] ~ ! ?"
        }
    }

    private func clearMozcHistory() {
        // Mozc runs inside the input method and holds its learning in memory:
        // ask it to clear (and save) that. The files go too, for when the
        // input method is not running.
        DistributedNotificationCenter.default().postNotificationName(
            MozcNotifications.clearLearning, object: nil, userInfo: nil, deliverImmediately: true)

        let mozcDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozc")
        for file in ["segment.db", "boundary.db", ".history.db"] {
            try? FileManager.default.removeItem(at: mozcDir.appendingPathComponent(file))
        }

        historyCleared = true
    }
}

// MARK: - Keyboard Hint Row

private struct KeyboardHintRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .frame(width: 170, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}
