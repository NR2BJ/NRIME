import SwiftUI

struct DictionaryTab: View {
    @ObservedObject private var manager = UserDictionaryManager.shared
    @State private var searchText = ""
    @State private var selection = Set<UUID>()
    @State private var showingAddSheet = false
    @State private var editingEntry: UserDictionaryManager.DictionaryEntry? = nil
    @State private var showingDeleteConfirmation = false

    private var filteredEntries: [UserDictionaryManager.DictionaryEntry] {
        if searchText.isEmpty {
            return manager.entries
        }
        let query = searchText.lowercased()
        return manager.entries.filter {
            $0.key.lowercased().contains(query)
            || $0.value.lowercased().contains(query)
            || $0.comment.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField(String(localized: "dictionary.search"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Spacer()

                Text("\(manager.entries.count) \(String(localized: "dictionary.entriesCount"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help(String(localized: "dictionary.addEntry"))

                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "minus")
                }
                .help(String(localized: "dictionary.deleteSelected"))
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Table
            if manager.isLoading {
                Spacer()
                ProgressView(String(localized: "dictionary.loading"))
                Spacer()
            } else if manager.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("dictionary.noEntries")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("dictionary.addHint")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                Table(filteredEntries, selection: $selection) {
                    TableColumn(String(localized: "dictionary.columnReading")) { entry in
                        Text(entry.key)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn(String(localized: "dictionary.columnWord")) { entry in
                        Text(entry.value)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn(String(localized: "dictionary.columnPOS")) { entry in
                        Text(entry.pos.japaneseLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn(String(localized: "dictionary.columnComment")) { entry in
                        Text(entry.comment)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 100)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1, let id = ids.first,
                       let entry = manager.entries.first(where: { $0.id == id }) {
                        Button(String(localized: "dictionary.edit")) {
                            editingEntry = entry
                        }
                    }
                    Button(String(localized: "dictionary.delete"), role: .destructive) {
                        selection = ids
                        showingDeleteConfirmation = true
                    }
                } primaryAction: { ids in
                    // Double-click → edit
                    if ids.count == 1, let id = ids.first,
                       let entry = manager.entries.first(where: { $0.id == id }) {
                        editingEntry = entry
                    }
                }
            }

            Divider()

            // Auto-learning info
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("dictionary.autoLearnInfo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Error bar
            if let error = manager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.1))
            }
        }
        .onAppear {
            manager.load()
        }
        .sheet(isPresented: $showingAddSheet) {
            DictionaryEntryEditor(mode: .add) { key, value, pos, comment in
                manager.addEntry(key: key, value: value, pos: pos, comment: comment)
            }
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntryEditor(mode: .edit(entry)) { key, value, pos, comment in
                manager.updateEntry(id: entry.id, key: key, value: value, pos: pos, comment: comment)
            }
        }
        .alert(String(format: String(localized: "dictionary.deleteConfirm"), selection.count), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) { }
            Button(String(localized: "dictionary.delete"), role: .destructive) {
                manager.deleteEntries(ids: selection)
                selection.removeAll()
            }
        } message: {
            Text("dictionary.deleteMessage")
        }
    }
}

// MARK: - Entry Editor Sheet

private struct DictionaryEntryEditor: View {
    enum Mode {
        case add
        case edit(UserDictionaryManager.DictionaryEntry)
    }

    let mode: Mode
    let onSave: (String, String, UserDictionaryManager.PosType, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var value: String = ""
    @State private var pos: UserDictionaryManager.PosType = .noun
    @State private var comment: String = ""

    private var title: String {
        switch mode {
        case .add: return String(localized: "dictionary.addTitle")
        case .edit: return String(localized: "dictionary.editTitle")
        }
    }

    private var isValid: Bool {
        !key.trimmingCharacters(in: .whitespaces).isEmpty
        && !value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(title)
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Form {
                TextField(String(localized: "dictionary.fieldReading"), text: $key)
                    .textFieldStyle(.roundedBorder)

                TextField(String(localized: "dictionary.fieldWord"), text: $value)
                    .textFieldStyle(.roundedBorder)

                Picker(String(localized: "dictionary.fieldPOS"), selection: $pos) {
                    ForEach(UserDictionaryManager.PosType.allCases) { posType in
                        Text("\(posType.rawValue) (\(posType.japaneseLabel))")
                            .tag(posType)
                    }
                }

                TextField(String(localized: "dictionary.fieldComment"), text: $comment)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20)

            // Buttons
            HStack {
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "dictionary.save")) {
                    onSave(
                        key.trimmingCharacters(in: .whitespaces),
                        value.trimmingCharacters(in: .whitespaces),
                        pos,
                        comment.trimmingCharacters(in: .whitespaces)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 280)
        .onAppear {
            if case .edit(let entry) = mode {
                key = entry.key
                value = entry.value
                pos = entry.pos
                comment = entry.comment
            }
        }
    }
}
