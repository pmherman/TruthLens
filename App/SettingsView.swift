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
                    Label("Web search checks the claims attached to the media", systemImage: "globe")
                }
                .font(.subheadline)
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
