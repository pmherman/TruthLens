import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $model.apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Link("Get a key at console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: { Text("Anthropic API key") } footer: {
                    Text("Stored only in this device's Keychain. Images are sent to Anthropic for analysis; nothing goes anywhere else.")
                }
                Section("How it works") {
                    Label("Reads file metadata and Content Credentials on-device", systemImage: "cpu")
                    Label("Claude inspects the pixels for generation tells", systemImage: "eye")
                    Label("Fact Check searches independent sources for any claim you paste", systemImage: "globe")
                }
                .font(.subheadline)
                Section("About") {
                    LabeledContent("TruthLens", value: AppInfo.versionString)
                        .accessibilityElement(children: .combine)
                    LabeledContent("Developed by", value: "Paul Herman")
                    Link(destination: AppInfo.repoURL) {
                        Label("GitHub: pmherman/TruthLens", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: AppInfo.repoURL.appendingPathComponent("issues")) {
                        Label("Report a bug or suggest a feature", systemImage: "ladybug")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/pmherman/TruthLens")!

    /// "Version 0.0.1 (1)", with an "Alpha" tag while the app is pre-1.0.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let stage = version.hasPrefix("0.") ? " Alpha" : ""
        return "Version \(version) (\(build))\(stage)"
    }
}
