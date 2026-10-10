import SwiftUI
import TruthLensCore

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
                } header: { Text("Anthropic API key (optional)") } footer: {
                    Text("A key unlocks fact checks, visual AI analysis and checking challenges against sources. It's stored only in this device's Keychain. When used, claims and images are sent to Anthropic, which bills you directly: \(model.pricing.summary).")
                }
                Section {
                    LabeledContent("Apple Intelligence", value: model.onDevice.isAvailable ? "Available" : "Not available")
                    Toggle("Use on-device model for replies and notes", isOn: $model.preferOnDevice)
                        .disabled(!model.onDevice.isAvailable)
                    Toggle("Visual analysis with Claude", isOn: $model.cloudScan)
                        .disabled(!model.hasKey)
                } header: { Text("On this device (free)") } footer: {
                    Text("\(model.onDevice.message) The on-device model writes simpler replies than Claude, can't search the web, and may decline some political topics. Turn off visual analysis to keep scans on this device: only file metadata is checked and no image is sent to Anthropic.")
                }
                Section {
                    LabeledContent("This month", value: Money.format(model.usage.thisMonth.cost))
                    LabeledContent("All time", value: Money.format(model.usage.allTime.cost))
                    Button("See the full breakdown") { model.tab = .stats; dismiss() }
                } header: { Text("Your usage (estimate)") } footer: {
                    Text("Estimated from Anthropic's published rates. Your Anthropic Console has the exact bill.")
                }
                Section("What works without a key") {
                    Label("File metadata and Content Credentials checks", systemImage: "cpu")
                    Label("History, Stats and audio playback", systemImage: "clock.arrow.circlepath")
                    Label("Replies, notes and follow-up answers on Apple Intelligence", systemImage: "apple.intelligence")
                }
                .font(.subheadline)
                Section("What needs a key") {
                    Label("Claude inspects the pixels for generation tells", systemImage: "eye")
                    Label("Fact Check searches independent sources for any claim", systemImage: "globe")
                    Label("Challenges to a result are checked against sources", systemImage: "bubble.left.and.text.bubble.right")
                }
                .font(.subheadline)
                Section("About") {
                    LabeledContent("TruthLens", value: AppInfo.versionString)
                        .accessibilityElement(children: .combine)
                    LabeledContent("Developed by", value: AppInfo.developer)
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
            .onAppear { model.refreshOnDevice() }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}
