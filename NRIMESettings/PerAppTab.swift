import SwiftUI

struct PerAppTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable per-app language mode memory", isOn: $store.perAppModeEnabled)

                if store.perAppModeEnabled {
                    Picker("Mode", selection: $store.perAppModeType) {
                        Text("Whitelist — remember only listed apps").tag("whitelist")
                        Text("Blacklist — remember all except listed apps").tag("blacklist")
                    }
                    .pickerStyle(.radioGroup)
                }
            }

            if store.perAppModeEnabled {
                Section(store.perAppModeType == "whitelist" ? "Remembered Apps" : "Excluded Apps") {
                    if store.perAppModeList.isEmpty {
                        Text("No apps added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.perAppModeList, id: \.self) { bundleId in
                            HStack {
                                if let icon = appIcon(for: bundleId) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                }
                                Text(appName(for: bundleId))
                                Spacer()
                                Text(bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    store.perAppModeList.removeAll { $0 == bundleId }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button("Add App...") {
                        showingAppPicker = true
                    }
                    .fileImporter(
                        isPresented: $showingAppPicker,
                        allowedContentTypes: [.application],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            if let bundle = Bundle(url: url),
                               let bundleId = bundle.bundleIdentifier {
                                if !store.perAppModeList.contains(bundleId) {
                                    store.perAppModeList.append(bundleId)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        // Fallback: use last component of bundle ID
        return bundleId.components(separatedBy: ".").last ?? bundleId
    }

    private func appIcon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
