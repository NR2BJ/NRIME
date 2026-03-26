import Foundation

// MARK: - GitHub API Models

struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let publishedAt: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let size: Int
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadURL = "browser_download_url"
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

    private static let apiURL = "https://api.github.com/repos/NR2BJ/NRIME/releases/latest"
    private static let suiteName = "group.com.nrime.inputmethod"
    private static let lastCheckKey = "UpdateLastCheckTime"
    private static let etagKey = "UpdateETag"
    private static let checkInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    @Published var state: UpdateState = .idle
    @Published var latestRelease: GitHubRelease?

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

    /// Download the PKG for the latest release.
    func downloadUpdate() {
        guard case .available = state, let release = latestRelease else { return }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }),
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
        let script = "do shell script \"installer -pkg \\\"\(escapedPath)\\\" -target /\" with administrator privileges"

        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            do {
                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    if process.terminationStatus == 0 {
                        // Save installed PKG size for same-version change detection
                        if let asset = self?.latestRelease?.assets.first(where: { $0.name.hasSuffix(".pkg") }) {
                            self?.defaults?.set(asset.size, forKey: "lastInstalledPkgSize")
                        }
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
        if let release = latestRelease,
           let asset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }) {
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            state = .available(version: version, notes: release.body ?? "", size: Int64(asset.size))
        } else {
            state = .idle
        }
    }

    // MARK: - Check Logic

    private func check() async {
        await MainActor.run { state = .checking }

        guard let url = URL(string: Self.apiURL) else {
            await MainActor.run { state = .error("Invalid API URL.") }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        // Use ETag for conditional requests
        if let etag = defaults?.string(forKey: Self.etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { state = .error("Invalid response.") }
                return
            }

            // Save check time
            defaults?.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            // Save ETag
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults?.set(etag, forKey: Self.etagKey)
            }

            if http.statusCode == 304 {
                // Not modified — use cached release if we have one
                await MainActor.run {
                    if latestRelease != nil, state == .checking {
                        state = .upToDate
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

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)

            let remoteVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            let newerVersion = compareVersions(current: currentVersion, remote: remoteVersion)
            let pkgAsset = release.assets.first(where: { $0.name.hasSuffix(".pkg") })
            let pkgSize = pkgAsset?.size ?? 0

            // Detect same-version re-uploads by comparing asset size
            let sameVersionChanged: Bool = {
                guard !newerVersion, let asset = pkgAsset else { return false }
                let savedSize = defaults?.integer(forKey: "lastInstalledPkgSize") ?? 0
                return savedSize > 0 && asset.size != savedSize
            }()

            await MainActor.run {
                self.latestRelease = release
                if newerVersion || sameVersionChanged {
                    let label = sameVersionChanged ? "\(remoteVersion) (updated)" : remoteVersion
                    state = .available(version: label, notes: release.body ?? "", size: Int64(pkgSize))
                } else {
                    // Record current PKG size for future same-version change detection
                    if let asset = pkgAsset, (defaults?.integer(forKey: "lastInstalledPkgSize") ?? 0) == 0 {
                        defaults?.set(asset.size, forKey: "lastInstalledPkgSize")
                    }
                    state = .upToDate
                }
            }
        } catch is CancellationError {
            await MainActor.run { state = .idle }
        } catch {
            // Silently fail on network errors — don't crash the IME
            await MainActor.run { state = .idle }
        }
    }

    // MARK: - Version Comparison

    /// Returns true if remote is newer than current.
    private func compareVersions(current: String, remote: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(currentParts.count, remoteParts.count)
        for i in 0..<maxLen {
            let c = i < currentParts.count ? currentParts[i] : 0
            let r = i < remoteParts.count ? remoteParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
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
        let fileName = downloadTask.response?.suggestedFilename ?? "NRIME-update.pkg"
        let destination = cacheDir.appendingPathComponent(fileName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            state = .readyToInstall(path: destination.path)
        } catch {
            state = .error("Failed to save download: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }
}
