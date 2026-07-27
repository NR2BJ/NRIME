import AppKit
import CryptoKit
import Foundation

// MARK: - GitHub API Models

struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let publishedAt: String?
    let assets: [GitHubAsset]
    /// GitHub marks test builds with `prerelease: true`; `/releases/latest` omits them.
    let prerelease: Bool?
    let draft: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case publishedAt = "published_at"
        case assets
        case prerelease
        case draft
    }

    var isPrerelease: Bool { prerelease ?? false }
    var isDraft: Bool { draft ?? false }

    /// Version string without the tag's leading "v" (e.g. "1.0.9-beta.2").
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var pkgAsset: GitHubAsset? {
        assets.first { $0.name.hasSuffix(".pkg") }
    }
}

// MARK: - Update Channel

/// Which GitHub releases the app is willing to install.
enum UpdateChannel: String, Codable, CaseIterable {
    /// Final releases only — GitHub's `/releases/latest` already excludes prereleases.
    case stable
    /// Newest release of any kind, so test builds reach opted-in users.
    case beta
}

struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadURL: String
    let updatedAt: String?
    /// GitHub-computed content digest ("sha256:<hex>") — the integrity anchor
    /// for the downloaded PKG, which is later installed with admin rights.
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
        case updatedAt = "updated_at"
        case digest
    }
}

// MARK: - Update State

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, notes: String, size: Int64)
    case downloading(progress: Double)
    case readyToInstall(path: String)
    case installing
    case error(String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.checking, .checking),
             (.upToDate, .upToDate),
             (.installing, .installing):
            return true
        case let (.available(v1, n1, s1), .available(v2, n2, s2)):
            return v1 == v2 && n1 == n2 && s1 == s2
        case let (.downloading(p1), .downloading(p2)):
            return p1 == p2
        case let (.readyToInstall(p1), .readyToInstall(p2)):
            return p1 == p2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

// MARK: - UpdateManager

final class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateManager()

    private static let repoURL = "https://api.github.com/repos/NR2BJ/NRIME/releases"
    private static let suiteName = "group.com.nrime.inputmethod"
    private static let lastCheckKey = "UpdateLastCheckTime"
    private static let channelKey = "UpdateChannel"
    private static let checkInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    /// How many releases to scan on the beta channel when picking the newest build.
    private static let betaScanCount = 20

    @Published var state: UpdateState = .idle
    @Published var latestRelease: GitHubRelease?

    /// Release channel this install follows. Persisted in the App Group so the
    /// IME and the settings app agree.
    @Published var channel: UpdateChannel = .stable

    private var downloadTask: URLSessionDownloadTask?
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.suiteName) ?? UserDefaults.standard
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private override init() {
        super.init()
        if let raw = defaults?.string(forKey: Self.channelKey),
           let stored = UpdateChannel(rawValue: raw) {
            channel = stored
        }
    }

    // MARK: - Public API

    /// Check for updates if enough time has passed since last check.
    func checkIfNeeded() {
        guard let defs = defaults else { return }
        let lastCheck = defs.double(forKey: Self.lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck >= Self.checkInterval {
            Task { await check() }
        }
    }

    /// Force check for updates now.
    func checkNow() {
        Task { await check() }
    }

    /// Switch channels and re-check immediately.
    /// Any pending download is cancelled — it belongs to the previous channel.
    func setChannel(_ newChannel: UpdateChannel) {
        guard newChannel != channel else { return }
        downloadTask?.cancel()
        downloadTask = nil
        channel = newChannel
        defaults?.set(newChannel.rawValue, forKey: Self.channelKey)
        latestRelease = nil
        state = .idle
        Task { await check() }
    }

    /// Download the PKG for the latest release.
    func downloadUpdate() {
        guard case .available = state, let release = latestRelease else { return }

        guard let asset = release.pkgAsset,
              let url = URL(string: asset.browserDownloadURL) else {
            state = .error("No PKG found in release assets.")
            return
        }

        let cacheDir = cacheDirectory()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Remove old cached PKGs
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "pkg" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        state = .downloading(progress: 0)
        let task = downloadSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    /// Install the downloaded PKG using admin privileges.
    func installUpdate() {
        guard case .readyToInstall(let path) = state else { return }
        state = .installing

        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        // `with prompt` makes the panel say what is asking (otherwise it reads
        // "osascript"), and gives it a proper owning context.
        let script = "do shell script \"installer -pkg \\\"\(escapedPath)\\\" -target /\""
            + " with administrator privileges"
            + " with prompt \"NRIME needs to install an update.\""

        // This app is LSUIElement: a child process raising the authentication
        // panel from the background can leave that panel without keyboard
        // focus, so the user cannot type their password. Come forward first.
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            do {
                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    if process.terminationStatus == 0 {
                        // Clean up downloaded PKG
                        try? FileManager.default.removeItem(atPath: path)
                        self?.state = .idle
                    } else {
                        self?.state = .error("Installation failed (exit code \(process.terminationStatus)).")
                    }
                }
            } catch {
                await MainActor.run {
                    self?.state = .error("Failed to launch installer: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        // Restore available state
        if let release = latestRelease, let asset = release.pkgAsset {
            state = .available(version: release.version,
                               notes: release.body ?? "",
                               size: Int64(asset.size))
        } else {
            state = .idle
        }
    }

    // MARK: - Check Logic

    private func check() async {
        let activeChannel = await MainActor.run { () -> UpdateChannel in
            state = .checking
            return channel
        }

        guard let url = URL(string: endpoint(for: activeChannel)) else {
            await MainActor.run { state = .error("Invalid API URL.") }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        // Conditional request keeps us under GitHub's unauthenticated rate limit.
        // The ETag is per channel because each channel hits a different URL.
        if let etag = defaults?.string(forKey: etagKey(for: activeChannel)) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { state = .error("Invalid response.") }
                return
            }

            defaults?.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            if http.statusCode == 304 {
                // Unchanged since the last check — re-evaluate the cached release so a
                // pending update isn't reported as "up to date".
                await MainActor.run {
                    if let cached = cachedRelease(for: activeChannel) {
                        evaluate(cached, channel: activeChannel)
                    } else {
                        state = .upToDate
                    }
                }
                return
            }

            guard http.statusCode == 200 else {
                await MainActor.run { state = .error("GitHub API returned \(http.statusCode).") }
                return
            }

            guard let release = decodeRelease(from: data, channel: activeChannel) else {
                await MainActor.run { state = .upToDate }
                return
            }

            // Only store the ETag once the body actually parsed, otherwise a future
            // 304 would point at a release we never decoded.
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults?.set(etag, forKey: etagKey(for: activeChannel))
            }
            cacheRelease(release, for: activeChannel)

            await MainActor.run { evaluate(release, channel: activeChannel) }
        } catch is CancellationError {
            await MainActor.run { state = .idle }
        } catch {
            // Silently fail on network errors — don't crash the IME
            await MainActor.run { state = .idle }
        }
    }

    /// Decide whether `release` is worth offering and publish the resulting state.
    @MainActor
    private func evaluate(_ release: GitHubRelease, channel activeChannel: UpdateChannel) {
        latestRelease = release

        let remoteVersion = release.version
        let isNewer = SemanticVersion.isNewer(remote: remoteVersion, than: currentVersion)
        let pkgSize = release.pkgAsset?.size ?? 0
        let timestampKey = pkgTimestampKey(for: activeChannel)

        // Detect same-version re-uploads by comparing the asset's upload timestamp,
        // so a rebuilt test build under an unchanged tag still reaches beta users.
        let sameVersionChanged: Bool = {
            guard !isNewer,
                  let remoteTimestamp = release.pkgAsset?.updatedAt else { return false }
            let saved = defaults?.string(forKey: timestampKey) ?? ""
            return !saved.isEmpty && remoteTimestamp != saved
        }()

        if isNewer || sameVersionChanged {
            let label = sameVersionChanged ? "\(remoteVersion) (updated)" : remoteVersion
            state = .available(version: label, notes: release.body ?? "", size: Int64(pkgSize))
        } else {
            if let ts = release.pkgAsset?.updatedAt,
               (defaults?.string(forKey: timestampKey) ?? "").isEmpty {
                defaults?.set(ts, forKey: timestampKey)
            }
            state = .upToDate
        }
    }

    /// Stable reads GitHub's "latest" (prereleases excluded server-side);
    /// beta scans the release list and picks the highest version itself.
    private func decodeRelease(from data: Data, channel activeChannel: UpdateChannel) -> GitHubRelease? {
        let decoder = JSONDecoder()
        switch activeChannel {
        case .stable:
            return try? decoder.decode(GitHubRelease.self, from: data)
        case .beta:
            guard let releases = try? decoder.decode([GitHubRelease].self, from: data) else {
                return nil
            }
            // Highest version wins rather than first-in-list, so a stable release
            // published after a beta still supersedes it.
            return releases
                .filter { !$0.isDraft && $0.pkgAsset != nil }
                .max { lhs, rhs in
                    guard let left = SemanticVersion(lhs.version),
                          let right = SemanticVersion(rhs.version) else { return false }
                    return left < right
                }
        }
    }

    // MARK: - Per-channel storage

    private func endpoint(for activeChannel: UpdateChannel) -> String {
        switch activeChannel {
        case .stable: return "\(Self.repoURL)/latest"
        case .beta:   return "\(Self.repoURL)?per_page=\(Self.betaScanCount)"
        }
    }

    private func etagKey(for activeChannel: UpdateChannel) -> String {
        "UpdateETag_\(activeChannel.rawValue)"
    }

    private func pkgTimestampKey(for activeChannel: UpdateChannel) -> String {
        "lastInstalledPkgTimestamp_\(activeChannel.rawValue)"
    }

    private func cachedReleaseKey(for activeChannel: UpdateChannel) -> String {
        "UpdateCachedRelease_\(activeChannel.rawValue)"
    }

    private func cacheRelease(_ release: GitHubRelease, for activeChannel: UpdateChannel) {
        guard let data = try? JSONEncoder().encode(release) else { return }
        defaults?.set(data, forKey: cachedReleaseKey(for: activeChannel))
    }

    private func cachedRelease(for activeChannel: UpdateChannel) -> GitHubRelease? {
        guard let data = defaults?.data(forKey: cachedReleaseKey(for: activeChannel)) else {
            return nil
        }
        return try? JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Helpers

    private func cacheDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Caches/NRIME")
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        state = .downloading(progress: progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let cacheDir = cacheDirectory()
        // Name the file from the release metadata, not the response's
        // suggestedFilename (a server-influenced header), and strip any
        // path components either way.
        let fileName = (latestRelease?.pkgAsset?.name ?? "NRIME-update.pkg")
            .components(separatedBy: "/").last ?? "NRIME-update.pkg"
        let destination = cacheDir.appendingPathComponent(fileName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)

            // The PKG is installed with admin rights — refuse bytes that don't
            // match the sha256 digest the release metadata promised.
            if Self.fileMatchesDigest(at: destination,
                                      expected: latestRelease?.pkgAsset?.digest) == false {
                try? FileManager.default.removeItem(at: destination)
                state = .error("Downloaded file failed integrity verification.")
                return
            }

            // Save PKG timestamp now (before install kills the app via postinstall)
            if let ts = latestRelease?.pkgAsset?.updatedAt {
                defaults?.set(ts, forKey: pkgTimestampKey(for: channel))
            }
            state = .readyToInstall(path: destination.path)
        } catch {
            state = .error("Failed to save download: \(error.localizedDescription)")
        }
    }

    /// Compare a file's SHA-256 against a GitHub asset digest ("sha256:<hex>").
    /// Returns nil when no digest is available (older releases), true/false
    /// for a definite verdict. An unreadable file is a failed verification.
    static func fileMatchesDigest(at url: URL, expected: String?) -> Bool? {
        guard let expected, expected.lowercased().hasPrefix("sha256:") else { return nil }
        let expectedHex = String(expected.dropFirst("sha256:".count)).lowercased()

        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let actualHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return actualHex == expectedHex
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }
}
