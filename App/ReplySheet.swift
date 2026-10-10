import SwiftUI
import TruthLensCore

struct ReplySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let report: AnalysisReport

    @AppStorage("replyPlatform") private var platformRaw = ReplyPlatform.facebook.rawValue
    @AppStorage("replyTone") private var toneRaw = ReplyTone.calm.rawValue
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    private var platform: ReplyPlatform { ReplyPlatform(rawValue: platformRaw) ?? .facebook }
    private var limit: Int { platform.characterLimit }
    private var over: Bool { text.count > limit }

    var body: some View {
        NavigationStack {
            Form {
                Section("Where are you replying?") {
                    Picker("Platform", selection: $platformRaw) {
                        ForEach(ReplyPlatform.allCases) { p in
                            Text("\(p.title) · \(p.characterLimit.formatted()) chars").tag(p.rawValue)
                        }
                    }
                    Picker("Tone", selection: $toneRaw) {
                        ForEach(ReplyTone.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty && !busy {
                                Text("Tap Generate to draft a reply…").foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Text("\(text.count) / \(limit.formatted())")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(over ? .red : .secondary)
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                    }
                } header: { Text("Reply") } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button { Task { await generate() } } label: {
                        Label(text.isEmpty ? "Generate" : "Regenerate", systemImage: "sparkles")
                    }.disabled(busy)
                    Button {
                        Clipboard.copy(text); copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.disabled(text.isEmpty || over)
                    if !text.isEmpty { ShareLink(item: text) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reply")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: platformRaw) { _, _ in
                // Switching to a tighter platform trims the current draft so it always fits.
                if over { text = ReplyLength.fit(text, limit: limit) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .presentationDetents([.large])
    }

    private func generate() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            text = try await model.client.draftReply(for: report, platform: platform,
                                                     tone: ReplyTone(rawValue: toneRaw) ?? .calm)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
