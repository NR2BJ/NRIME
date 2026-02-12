import Foundation
import SwiftProtobuf

/// Manages Mozc user dictionary (protobuf read/write).
/// Path: ~/Library/Application Support/Mozc/user_dictionary.db
final class UserDictionaryManager: ObservableObject {

    static let shared = UserDictionaryManager()

    // MARK: - Published State

    @Published var entries: [DictionaryEntry] = []
    @Published var isLoading = false
    @Published var lastError: String? = nil

    // MARK: - Entry Model

    struct DictionaryEntry: Identifiable, Equatable {
        let id: UUID
        var key: String        // 읽기 (hiragana reading)
        var value: String      // 변환 (conversion result)
        var pos: PosType       // 품사 (part of speech)
        var comment: String    // 코멘트

        init(id: UUID = UUID(), key: String, value: String, pos: PosType = .noun, comment: String = "") {
            self.id = id
            self.key = key
            self.value = value
            self.pos = pos
            self.comment = comment
        }
    }

    /// Simplified POS types for UI (most commonly used subset).
    enum PosType: String, CaseIterable, Identifiable {
        case noun = "Noun"
        case properNoun = "Proper Noun"
        case personalName = "Personal Name"
        case familyName = "Family Name"
        case firstName = "First Name"
        case organizationName = "Organization"
        case placeName = "Place Name"
        case abbreviation = "Abbreviation"
        case suggestionOnly = "Suggestion Only"
        case symbol = "Symbol"
        case emoticon = "Emoticon"
        case adverb = "Adverb"
        case conjunction = "Conjunction"
        case interjection = "Interjection"
        case prefix = "Prefix"
        case counterSuffix = "Counter Suffix"
        case adjective = "Adjective"
        case suppressionWord = "Suppression"

        var id: String { rawValue }

        /// Japanese label for display.
        var japaneseLabel: String {
            switch self {
            case .noun: return "名詞"
            case .properNoun: return "固有名詞"
            case .personalName: return "人名"
            case .familyName: return "姓"
            case .firstName: return "名"
            case .organizationName: return "組織"
            case .placeName: return "地名"
            case .abbreviation: return "短縮よみ"
            case .suggestionOnly: return "サジェストのみ"
            case .symbol: return "記号"
            case .emoticon: return "顔文字"
            case .adverb: return "副詞"
            case .conjunction: return "接続詞"
            case .interjection: return "感動詞"
            case .prefix: return "接頭語"
            case .counterSuffix: return "助数詞"
            case .adjective: return "形容詞"
            case .suppressionWord: return "抑制単語"
            }
        }

        /// Convert to Mozc protobuf PosType.
        var mozcPosType: Mozc_UserDictionary_UserDictionary.PosType {
            switch self {
            case .noun: return .noun
            case .properNoun: return .properNoun
            case .personalName: return .personalName
            case .familyName: return .familyName
            case .firstName: return .firstName
            case .organizationName: return .organizationName
            case .placeName: return .placeName
            case .abbreviation: return .abbreviation
            case .suggestionOnly: return .suggestionOnly
            case .symbol: return .symbol
            case .emoticon: return .emoticon
            case .adverb: return .adverb
            case .conjunction: return .conjunction
            case .interjection: return .interjection
            case .prefix: return .prefix
            case .counterSuffix: return .counterSuffix
            case .adjective: return .adjective
            case .suppressionWord: return .suppressionWord
            }
        }

        /// Convert from Mozc protobuf PosType.
        static func from(mozcPos: Mozc_UserDictionary_UserDictionary.PosType) -> PosType {
            switch mozcPos {
            case .noun: return .noun
            case .properNoun: return .properNoun
            case .personalName: return .personalName
            case .familyName: return .familyName
            case .firstName: return .firstName
            case .organizationName: return .organizationName
            case .placeName: return .placeName
            case .abbreviation: return .abbreviation
            case .suggestionOnly: return .suggestionOnly
            case .symbol: return .symbol
            case .emoticon: return .emoticon
            case .adverb: return .adverb
            case .conjunction: return .conjunction
            case .interjection: return .interjection
            case .prefix: return .prefix
            case .counterSuffix: return .counterSuffix
            case .adjective: return .adjective
            case .suppressionWord: return .suppressionWord
            // Map less common types to noun
            default: return .noun
            }
        }
    }

    // MARK: - Paths

    private var mozcDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozc")
    }

    private var dictionaryPath: URL {
        mozcDir.appendingPathComponent("user_dictionary.db")
    }

    // MARK: - Internal State

    /// The raw protobuf storage (preserved for lossless save).
    private var storage = Mozc_UserDictionary_UserDictionaryStorage()

    /// Index of the dictionary within storage we're editing (default: first / only one).
    private var activeDictionaryIndex: Int = 0

    // MARK: - Load

    func load() {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        let path = dictionaryPath
        guard FileManager.default.fileExists(atPath: path.path) else {
            // No dictionary file yet — start empty
            storage = Mozc_UserDictionary_UserDictionaryStorage()
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: path)
            storage = try Mozc_UserDictionary_UserDictionaryStorage(serializedBytes: data)

            // Use first dictionary, or create one if none exist
            if storage.dictionaries.isEmpty {
                var dict = Mozc_UserDictionary_UserDictionary()
                dict.name = "User Dictionary"
                dict.id = UInt64(Date().timeIntervalSince1970 * 1000)
                storage.dictionaries.append(dict)
                activeDictionaryIndex = 0
            } else {
                activeDictionaryIndex = 0
            }

            // Convert protobuf entries to our model
            let dict = storage.dictionaries[activeDictionaryIndex]
            entries = dict.entries.map { entry in
                DictionaryEntry(
                    key: entry.key,
                    value: entry.value,
                    pos: PosType.from(mozcPos: entry.pos),
                    comment: entry.comment
                )
            }
        } catch {
            lastError = "Failed to load dictionary: \(error.localizedDescription)"
            entries = []
        }
    }

    // MARK: - Save

    @discardableResult
    func save() -> Bool {
        lastError = nil

        // Ensure directory exists
        let dir = mozcDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                lastError = "Failed to create Mozc directory: \(error.localizedDescription)"
                return false
            }
        }

        // Ensure at least one dictionary exists
        if storage.dictionaries.isEmpty {
            var dict = Mozc_UserDictionary_UserDictionary()
            dict.name = "User Dictionary"
            dict.id = UInt64(Date().timeIntervalSince1970 * 1000)
            storage.dictionaries.append(dict)
            activeDictionaryIndex = 0
        }

        // Convert our model back to protobuf entries
        storage.dictionaries[activeDictionaryIndex].entries = entries.map { entry in
            var pbEntry = Mozc_UserDictionary_UserDictionary.Entry()
            pbEntry.key = entry.key
            pbEntry.value = entry.value
            pbEntry.pos = entry.pos.mozcPosType
            if !entry.comment.isEmpty {
                pbEntry.comment = entry.comment
            }
            return pbEntry
        }

        do {
            let data = try storage.serializedData()
            try data.write(to: dictionaryPath, options: .atomic)

            // Restart mozc_server so it picks up the new dictionary
            restartMozcServer()
            return true
        } catch {
            lastError = "Failed to save dictionary: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - CRUD

    func addEntry(key: String, value: String, pos: PosType = .noun, comment: String = "") {
        let entry = DictionaryEntry(key: key, value: value, pos: pos, comment: comment)
        entries.append(entry)
        save()
    }

    func updateEntry(id: UUID, key: String, value: String, pos: PosType, comment: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].key = key
        entries[index].value = value
        entries[index].pos = pos
        entries[index].comment = comment
        save()
    }

    func deleteEntries(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Helpers

    private func restartMozcServer() {
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-f", "mozc_server"]
        try? task.run()
        task.waitUntilExit()
    }
}
