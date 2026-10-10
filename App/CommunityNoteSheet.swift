import SwiftUI
import TruthLensCore

/// Drafts a Meta Community Note from a fact check: neutral note text plus one source link, within Meta's limit.
struct CommunityNoteSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let report: FactCheckReport

    @State private var body_ = ""
    @State private var sourceID: String
    @State private var busy = false
    @State private var error: String?
    @State private var copied = false

    init(report: FactCheckReport) {
        self.report = report
        _sourceID = State(initialValue: CommunityNote.bestSource(for: report)?.id ?? "")
    }

    private var source: FactSource? { report.sources.first { $0.id == sourceID } }
    private var composed: String { source.map { CommunityNote.compose(body: body_, source: $0) } ?? "" }
    private var budget: Int { source.map(CommunityNote.bodyBudget) ?? CommunityNote.characterLimit }
    private var total: Int { body_.isEmpty ? 0 : body_.count + 1 + (source?.url.count ?? 0) }
    private var over: Bool { total > CommunityNote.characterLimit }

    var body: some View {
        NavigationStack {
            Form {
                if !CommunityNote.isUsuallyWarranted(report.rating) {
                    Section {
                        Label("This claim was rated \(report.rating.title). Community Notes are meant for adding missing context, so a note may not be needed.",
                              systemImage: "info.circle")
                            .font(.subheadline)
                    }
                }
                Section {
                    Picker("Source link", selection: $sourceID) {
                        ForEach(report.sources) { src in
                            Text("\(src.publisher) · \(src.stance.label)").tag(src.id)
                        }
                    }
                } header: { Text("Link to include") } footer: {
                    Text("Meta requires a link to a source that supports the note.")
                }
                Section {
                    TextEditor(text: $body_)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Community note text")
                        .overlay(alignment: .topLeading) {
                            if body_.isEmpty && !busy {
                                Text("Tap Generate to draft a note…").foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Text("\(total) / \(CommunityNote.characterLimit) incl. link")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(over ? .red : .secondary)
                        Spacer()
                        if busy { ProgressView().controlSize(.small) }
                    }
                } header: { Text("Note") } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                    else { Text("Notes can't be edited after you submit them, so review the text first.") }
                }
                Section {
                    Button { Task { await generate() } } label: {
                        Label(body_.isEmpty ? "Generate" : "Regenerate", systemImage: "sparkles")
                    }.disabled(busy || source == nil)
                    Button {
                        Clipboard.copy(composed); copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy note + link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.disabled(body_.isEmpty || over)
                    if !body_.isEmpty && !over { ShareLink(item: composed) }
                    ListenControls(text: body_)
                } footer: {
                    Text("Paste it into Meta: open the post's ••• menu and choose Write community note.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Community Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: sourceID) { _, _ in
                // A longer link leaves less room for text; keep the note inside the limit.
                if over, let source { body_ = ReplyLength.fit(body_, limit: CommunityNote.bodyBudget(source: source)) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .presentationDetents([.large])
    }

    private func generate() async {
        guard let source else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            body_ = try await app.client.draftCommunityNote(for: report, source: source)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
