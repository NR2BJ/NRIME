import Foundation

struct HanjaSelectionEntry: Codable, Equatable {
    let hangul: String
    let hanja: String
}

final class HanjaSelectionStore {
    static let defaultsKey = "hanjaSelectionMemory"
    static let suiteName = "group.com.nrime.inputmethod"

    private let defaults: UserDefaults
    private let maxEntries: Int

    init(defaults: UserDefaults? = nil, maxEntries: Int = 200) {
        self.defaults = defaults ?? (UserDefaults(suiteName: Self.suiteName) ?? UserDefaults.standard)
        self.maxEntries = maxEntries
    }

    func remember(hanja: String, for hangul: String) {
        let normalizedHangul = hangul.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHanja = hanja.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHangul.isEmpty, !normalizedHanja.isEmpty else { return }

        var entries = loadEntries().filter { $0.hangul != normalizedHangul }
        entries.insert(HanjaSelectionEntry(hangul: normalizedHangul, hanja: normalizedHanja), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveEntries(entries)
    }

    func prioritize(
        _ results: [(hanja: String, meaning: String)],
        for hangul: String
    ) -> [(hanja: String, meaning: String)] {
        guard let preferredHanja = preferredHanja(for: hangul),
              let preferredIndex = results.firstIndex(where: { $0.hanja == preferredHanja }) else {
            return results
        }

        var reordered = results
        let preferred = reordered.remove(at: preferredIndex)
        reordered.insert(preferred, at: 0)
        return reordered
    }

    func preferredHanja(for hangul: String) -> String? {
        let normalizedHangul = hangul.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHangul.isEmpty else { return nil }
        return loadEntries().first(where: { $0.hangul == normalizedHangul })?.hanja
    }

    private func loadEntries() -> [HanjaSelectionEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([HanjaSelectionEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveEntries(_ entries: [HanjaSelectionEntry]) {
        guard !entries.isEmpty else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
