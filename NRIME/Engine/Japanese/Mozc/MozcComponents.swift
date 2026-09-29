import Foundation

/// A Mozc engine NRIME can load: libnrime_mozc.dylib and the mozc.data built
/// with it. One ships in the app; newer ones are downloaded by MozcUpdater
/// (built by the component workflow from upstream Mozc), so Mozc can be
/// updated without a new NRIME.
struct MozcComponent: Equatable {
    enum Source: String {
        case bundled
        case downloaded
    }

    let source: Source
    let libraryURL: URL
    let dataURL: URL
    let commit: String
    /// Upstream commit date, yyyy-MM-dd — what "newer" means.
    let date: String
    let version: String
    /// Where a downloaded component's files and state live.
    let directory: URL?

    var info: MozcStatus.Build {
        MozcStatus.Build(version: version, date: date, commit: commit)
    }
}

/// Finding, choosing and guarding components.
///
/// A downloaded engine that fails runs NRIME without Japanese conversion at
/// best, or crashes the input method at every start at worst. So: a
/// component that fails to load, or whose load never finished (the process
/// died during it), or that saw three starts within ten minutes (a crash
/// loop), is marked bad and never tried again; the bundled one takes over.
enum MozcComponents {
    /// The C API version this NRIME speaks (NRIME_MOZC_ABI_VERSION).
    static let supportedABI = 1

    static let libraryName = "libnrime_mozc.dylib"
    static let dataName = "mozc.data"
    static let manifestName = "manifest.json"

    /// ~/Library/Application Support/NRIME/Mozc/<commit>/ for downloads.
    static var downloadsDirectory: URL {
#if DEBUG
        if let override = downloadsDirectoryForTesting { return override }
        if AppGroupDefaults.isRunningTests {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("NRIME-test-mozc-components-\(ProcessInfo.processInfo.processIdentifier)")
        }
#endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NRIME/Mozc")
    }

#if DEBUG
    static var downloadsDirectoryForTesting: URL?
    static var bundledForTesting: MozcComponent??
#endif

    // MARK: - Finding

    /// The one in the app: Frameworks/libnrime_mozc.dylib, Resources/mozc.data
    /// and Resources/MOZC_VERSION ("<commit> <date> <version>").
    static var bundled: MozcComponent? {
#if DEBUG
        if let forced = bundledForTesting { return forced }
#endif
        guard let library = Bundle.main.privateFrameworksURL?.appendingPathComponent(libraryName),
              FileManager.default.fileExists(atPath: library.path),
              let data = Bundle.main.url(forResource: "mozc", withExtension: "data"),
              let versionFile = Bundle.main.url(forResource: "MOZC_VERSION", withExtension: nil),
              let line = try? String(contentsOf: versionFile, encoding: .utf8) else { return nil }
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 3 else { return nil }
        return MozcComponent(source: .bundled, libraryURL: library, dataURL: data,
                             commit: parts[0], date: parts[1], version: parts[2], directory: nil)
    }

    struct Manifest: Codable, Equatable {
        let abi: Int
        let commit: String
        let date: String
        let version: String
        /// File name → SHA-256 (hex).
        let files: [String: String]
    }

    /// Downloaded components that may be loaded: complete, of our ABI, not bad.
    static func downloaded() -> [MozcComponent] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: downloadsDirectory,
                                                        includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { directory -> MozcComponent? in
            guard !directory.lastPathComponent.hasPrefix("."),
                  !fm.fileExists(atPath: directory.appendingPathComponent(State.bad.rawValue).path),
                  let data = try? Data(contentsOf: directory.appendingPathComponent(manifestName)),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  manifest.abi == supportedABI else { return nil }
            let library = directory.appendingPathComponent(libraryName)
            let mozcData = directory.appendingPathComponent(dataName)
            guard fm.fileExists(atPath: library.path), fm.fileExists(atPath: mozcData.path) else { return nil }
            return MozcComponent(source: .downloaded, libraryURL: library, dataURL: mozcData,
                                 commit: manifest.commit, date: manifest.date, version: manifest.version,
                                 directory: directory)
        }
    }

    /// Engines to try, best first: downloaded ones newer than the bundled
    /// one (newest first), then the bundled one.
    static func candidates() -> [MozcComponent] {
        let base = bundled
        let newer = downloaded()
            .filter { component in
                guard let base else { return true }
                return isNewer(component, than: base)
            }
            .sorted { isNewer($0, than: $1) }
        return newer + (base.map { [$0] } ?? [])
    }

    /// Newer by upstream commit date, then Mozc version; the same commit is never newer.
    static func isNewer(_ lhs: MozcComponent, than rhs: MozcComponent) -> Bool {
        guard lhs.commit != rhs.commit else { return false }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        guard let left = SemanticVersion(lhs.version), let right = SemanticVersion(rhs.version) else { return false }
        return right < left
    }

    /// Commits of components marked bad — never downloaded again.
    static func badCommits() -> Set<String> {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: downloadsDirectory,
                                                        includingPropertiesForKeys: nil) else { return [] }
        return Set(entries.compactMap { directory -> String? in
            guard fm.fileExists(atPath: directory.appendingPathComponent(State.bad.rawValue).path) else { return nil }
            return directory.lastPathComponent
        })
    }

    // MARK: - Guarding

    enum State: String {
        /// Written before a load, removed when it finished: found at the next
        /// start, it means the process died loading this component.
        case loading
        /// Never load this component again.
        case bad
        /// Start times (one per line), for spotting a crash loop.
        case starts
    }

    /// Called before loading a downloaded component. False when it must not
    /// be loaded (and it is marked bad): its last load never finished, or it
    /// has been started three times within ten minutes.
    static func beginLoad(_ component: MozcComponent, now: Date = Date()) -> Bool {
        guard let directory = component.directory else { return true }
        let loading = directory.appendingPathComponent(State.loading.rawValue)
        if FileManager.default.fileExists(atPath: loading.path) {
            markBad(component, reason: "an earlier load never finished")
            return false
        }
        let startsFile = directory.appendingPathComponent(State.starts.rawValue)
        let earlier = ((try? String(contentsOf: startsFile, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .compactMap { TimeInterval(String($0)) }
            .map(Date.init(timeIntervalSince1970:))
        let recent = (earlier + [now]).filter { now.timeIntervalSince($0) < 600 }
        if recent.count >= 3 {
            markBad(component, reason: "started \(recent.count) times in ten minutes")
            return false
        }
        let kept = (earlier + [now]).suffix(5).map { String($0.timeIntervalSince1970) }
        try? kept.joined(separator: "\n").write(to: startsFile, atomically: true, encoding: .utf8)
        try? Data().write(to: loading)
        return true
    }

    /// The load finished (engine created and answering).
    static func endLoad(_ component: MozcComponent) {
        guard let directory = component.directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(State.loading.rawValue))
    }

    static func markBad(_ component: MozcComponent, reason: String) {
        guard let directory = component.directory else { return }
        try? reason.write(to: directory.appendingPathComponent(State.bad.rawValue), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(State.loading.rawValue))
        DeveloperLogger.shared.log("Mozc", "Component marked bad", metadata: [
            "version": component.version, "commit": String(component.commit.prefix(7)), "reason": reason,
        ])
    }

    /// Keep the two newest good downloads (the one in use and one to fall
    /// back to) and delete older ones. A bad one keeps only its marker, so
    /// the same build is not downloaded again.
    static func prune(keeping active: MozcComponent?) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: downloadsDirectory,
                                                        includingPropertiesForKeys: nil) else { return }
        let good = downloaded().sorted { isNewer($0, than: $1) }
        var keep = Set(good.prefix(2).compactMap { $0.directory?.standardizedFileURL })
        if let directory = active?.directory { keep.insert(directory.standardizedFileURL) }
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            if fm.fileExists(atPath: entry.appendingPathComponent(State.bad.rawValue).path) {
                try? fm.removeItem(at: entry.appendingPathComponent(libraryName))
                try? fm.removeItem(at: entry.appendingPathComponent(dataName))
            } else if !keep.contains(entry.standardizedFileURL) {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
