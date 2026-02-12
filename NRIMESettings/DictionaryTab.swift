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
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Spacer()

                Text("\(manager.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Add Entry")

                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "minus")
                }
                .help("Delete Selected")
                .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Table
            if manager.isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if manager.entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No dictionary entries")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click + to add a word")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                Table(filteredEntries, selection: $selection) {
                    TableColumn("Reading") { entry in
                        Text(entry.key)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Word") { entry in
                        Text(entry.value)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("POS") { entry in
                        Text(entry.pos.japaneseLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Comment") { entry in
                        Text(entry.comment)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 100)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1, let id = ids.first,
                       let entry = manager.entries.first(where: { $0.id == id }) {
                        Button("Edit...") {
                            editingEntry = entry
                        }
                    }
                    Button("Delete", role: .destructive) {
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
                Text("Auto-learned conversions are stored as hashes and cannot be listed. To clear them, go to the **Japanese** tab → Clear Conversion History.")
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
        .alert("Delete \(selection.count) entry(ies)?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                manager.deleteEntries(ids: selection)
                selection.removeAll()
            }
        } message: {
            Text("This cannot be undone. The word(s) will be removed from your user dictionary.")
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
        case .add: return "Add Entry"
        case .edit: return "Edit Entry"
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
                TextField("Reading (hiragana):", text: $key)
                    .textFieldStyle(.roundedBorder)

                TextField("Word (conversion):", text: $value)
                    .textFieldStyle(.roundedBorder)

                Picker("Part of Speech:", selection: $pos) {
                    ForEach(UserDictionaryManager.PosType.allCases) { posType in
                        Text("\(posType.rawValue) (\(posType.japaneseLabel))")
                            .tag(posType)
                    }
                }

                TextField("Comment (optional):", text: $comment)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 20)

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
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
