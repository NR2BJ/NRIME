import SwiftUI

struct AboutTab: View {
    @AppStorage("appLanguage") private var appLanguage: String = "ko"
    private let githubURL = "https://github.com/NR2BJ/NRIME"
    @StateObject private var updateManager = UpdateManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(verbatim: "NRIME")
                .font(.largeTitle.bold())

            Text("about.subtitle")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)

            Divider()
                .frame(maxWidth: 200)

            Text("about.languages")
                .font(.body)

            Link(destination: URL(string: githubURL)!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text(verbatim: "GitHub")
                }
                .font(.body)
            }

            Divider()
                .frame(maxWidth: 200)

            updateSection

            Divider()
                .frame(maxWidth: 200)

            VStack(spacing: 8) {
                Picker(String(localized: "about.language"), selection: $appLanguage) {
                    Text(verbatim: "\u{D55C}\u{AD6D}\u{C5B4}").tag("ko")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "\u{65E5}\u{672C}\u{8A9E}").tag("ja")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Text("about.languageRestart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            updateManager.checkIfNeeded()
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updateManager.state {
        case .idle:
            checkButton

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            VStack(spacing: 8) {
                Label("You're up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                checkButton
            }

        case .available(let version, let notes, let size):
            VStack(spacing: 12) {
                Label("Update Available: v\(version)", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                if !notes.isEmpty {
                    Text(releaseNotesSummary(notes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .lineLimit(4)
                }

                if size > 0 {
                    Text(formatBytes(size))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    updateManager.downloadUpdate()
                } label: {
                    Label("Download & Install", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
            }

        case .downloading(let progress):
            VStack(spacing: 8) {
                Text("Downloading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .frame(maxWidth: 200)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Button("Cancel") {
                    updateManager.cancelDownload()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)
            }

        case .readyToInstall:
            VStack(spacing: 8) {
                Text("Download complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    updateManager.installUpdate()
                } label: {
                    Label("Install Now", systemImage: "arrow.uturn.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }

        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing...")
                    .foregroundStyle(.secondary)
            }

        case .error(let message):
            VStack(spacing: 8) {
                Label("Update Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button {
            updateManager.checkNow()
        } label: {
            Label("Check for Updates", systemImage: "arrow.clockwise")
        }
    }

    private func releaseNotesSummary(_ notes: String) -> String {
        // Return first few lines as summary
        let lines = notes.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let summary = lines.prefix(4).joined(separator: "\n")
        return summary
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
