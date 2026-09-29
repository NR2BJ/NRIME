import Foundation

/// Looks for a newer Mozc on GitHub and downloads it, so Mozc is updated on
/// this Mac without a new NRIME.
///
/// The component workflow (.github/workflows/mozc-component.yml) builds each
/// new upstream Mozc version or dictionary on GitHub's machines, tests it with
/// NRIME, and publishes it as a prerelease tagged mozc-<abi>-<yyyymmdd>-<commit7>
/// carrying nrime-mozc.zip (libnrime_mozc.dylib, mozc.data, manifest.json).
/// App updates ignore those releases: they have no .pkg.
///
/// Checked a few minutes after the input method starts, then daily. Nothing
/// is sent but the request for the release list. A download must match the
/// SHA-256 GitHub records for the file and the manifest's per-file hashes;
/// it is used from the next start of the input method (Settings > About can
/// apply it at once).
final class MozcUpdater {
    static let shared = MozcUpdater()

    static let releasesURL = URL(string: "https://api.github.com/repos/NR2BJ/NRIME/releases?per_page=50")!
    static let assetName = "nrime-mozc.zip"
    static let tagPrefix = "mozc-"
    private static let firstCheckDelay: TimeInterval = 5 * 60
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var timer: Timer?
    private var checking = false

    private init() {}

    /// A component on offer.
    struct Offer: Equatable {
        let abi: Int
        /// yyyy-MM-dd
        let date: String
        let commitPrefix: String
        let downloadURL: URL
        /// "sha256:<hex>", as GitHub reports it.
        let digest: String
    }

    // MARK: - Scheduling (main thread)

    func start() {
        if AppGroupDefaults.isRunningTests { return }
        DistributedNotificationCenter.default().addObserver(
            forName: MozcNotifications.checkForUpdate, object: nil, queue: .main
        ) { _ in
            MozcUpdater.shared.checkNow()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.firstCheckDelay, repeats: false) { _ in
            MozcUpdater.shared.checkNow()
            MozcUpdater.shared.timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval,
                                                            repeats: true) { _ in
                MozcUpdater.shared.checkNow()
            }
        }
    }

    func checkNow() {
        guard !checking else { return }
        checking = true
        // What is here already: the engine in use and every download.
        let installed = (MozcEngine.shared.active.map { [$0] } ?? []) + MozcComponents.downloaded()
        let bad = MozcComponents.badCommits()
        Task.detached(priority: .utility) {
            let outcome = await Self.check(installed: installed, bad: bad)
            await MainActor.run {
                MozcUpdater.shared.checking = false
                // A failed check (offline, GitHub down) is not a check.
                if case .failed = outcome { return }
                MozcEngine.updateStatus { status in
                    status.checkedAt = Date()
                    if case .downloaded(let component) = outcome {
                        status.pending = component.info
                    }
                }
            }
        }
    }

    // MARK: - Checking (off the main thread)

    enum Outcome {
        case upToDate
        case downloaded(MozcComponent)
        case failed(String)
    }

    private static func check(installed: [MozcComponent], bad: Set<String>) async -> Outcome {
        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return log(.failed("HTTP")) }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let offer = newest(in: releases, abi: MozcComponents.supportedABI, bad: bad) else {
                return log(.upToDate)
            }
            guard isWanted(offer, installed: installed) else { return log(.upToDate) }

            let (file, _) = try await URLSession.shared.download(from: offer.downloadURL)
            defer { try? FileManager.default.removeItem(at: file) }
            let component = try install(zip: file, offer: offer, into: MozcComponents.downloadsDirectory)
            return log(.downloaded(component))
        } catch {
            return log(.failed("\(error)"))
        }
    }

    @discardableResult
    private static func log(_ outcome: Outcome) -> Outcome {
        switch outcome {
        case .upToDate:
            DeveloperLogger.shared.log("Mozc", "Update check: up to date")
        case .downloaded(let component):
            DeveloperLogger.shared.log("Mozc", "Update downloaded", metadata: [
                "version": component.version, "date": component.date,
                "commit": String(component.commit.prefix(7)),
            ])
        case .failed(let reason):
            DeveloperLogger.shared.log("Mozc", "Update check failed", metadata: ["reason": reason])
        }
        return outcome
    }

    /// The component a release offers: tag mozc-<abi>-<yyyymmdd>-<commit7>,
    /// an nrime-mozc.zip asset, and GitHub's digest for it.
    static func offer(from release: GitHubRelease) -> Offer? {
        guard !release.isDraft, release.tagName.hasPrefix(tagPrefix) else { return nil }
        let parts = release.tagName.dropFirst(tagPrefix.count).split(separator: "-").map(String.init)
        guard parts.count == 3,
              let abi = Int(parts[0]),
              parts[1].count == 8, Int(parts[1]) != nil,
              parts[2].count >= 7, parts[2].allSatisfy(\.isHexDigit),
              let asset = release.assets.first(where: { $0.name == assetName }),
              let url = URL(string: asset.browserDownloadURL),
              let digest = asset.digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let d = parts[1]
        let date = "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2))"
        return Offer(abi: abi, date: date, commitPrefix: parts[2].lowercased(), downloadURL: url, digest: digest)
    }

    /// The newest component for this ABI that has not gone bad here.
    static func newest(in releases: [GitHubRelease], abi: Int, bad: Set<String>) -> Offer? {
        releases
            .compactMap(offer(from:))
            .filter { offer in
                offer.abi == abi && !bad.contains(where: { $0.lowercased().hasPrefix(offer.commitPrefix) })
            }
            .max { $0.date < $1.date }
    }

    /// Worth downloading: newer than everything here, and not already here.
    static func isWanted(_ offer: Offer, installed: [MozcComponent]) -> Bool {
        !installed.contains { component in
            component.commit.lowercased().hasPrefix(offer.commitPrefix) || component.date >= offer.date
        }
    }

    enum InstallError: Error {
        case digestMismatch
        case unzipFailed
        case badManifest(String)
    }

    /// Verify and unpack a downloaded nrime-mozc.zip into
    /// <downloads>/<commit>/, where MozcComponents finds it.
    static func install(zip: URL, offer: Offer, into downloads: URL) throws -> MozcComponent {
        guard UpdateManager.fileMatchesDigest(at: zip, expected: offer.digest) == true else {
            throw InstallError.digestMismatch
        }
        let fm = FileManager.default
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let staging = downloads.appendingPathComponent(".staging-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, staging.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw InstallError.unzipFailed }

        let manifestData = try Data(contentsOf: staging.appendingPathComponent(MozcComponents.manifestName))
        let manifest = try JSONDecoder().decode(MozcComponents.Manifest.self, from: manifestData)
        guard manifest.abi == offer.abi, manifest.abi == MozcComponents.supportedABI else {
            throw InstallError.badManifest("ABI \(manifest.abi)")
        }
        guard manifest.commit.lowercased().hasPrefix(offer.commitPrefix), manifest.date == offer.date else {
            throw InstallError.badManifest("commit or date differs from the release")
        }
        for name in [MozcComponents.libraryName, MozcComponents.dataName] {
            guard let hex = manifest.files[name],
                  UpdateManager.fileMatchesDigest(at: staging.appendingPathComponent(name),
                                                  expected: "sha256:\(hex)") == true else {
                throw InstallError.badManifest("\(name) does not match its hash")
            }
        }
        // Downloads can carry quarantine; a quarantined library may be refused.
        for name in [MozcComponents.libraryName, MozcComponents.dataName, MozcComponents.manifestName] {
            removexattr(staging.appendingPathComponent(name).path, "com.apple.quarantine", 0)
        }

        let destination = downloads.appendingPathComponent(manifest.commit)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: staging, to: destination)
        return MozcComponent(source: .downloaded,
                             libraryURL: destination.appendingPathComponent(MozcComponents.libraryName),
                             dataURL: destination.appendingPathComponent(MozcComponents.dataName),
                             commit: manifest.commit, date: manifest.date, version: manifest.version,
                             directory: destination)
    }
}
