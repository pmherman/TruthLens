import SwiftUI
import PhotosUI
import TruthLensCore

extension ClaimRating {
    var color: Color {
        switch self {
        case .true_: .green
        case .mostlyTrue: .mint
        case .partiallyTrue: .yellow
        case .misleading: .orange
        case .mostlyFalse: .orange
        case .false_: .red
        case .unverified, .notCheckable: .gray
        }
    }

    var symbol: String {
        switch self {
        case .true_, .mostlyTrue: "checkmark.circle.fill"
        case .partiallyTrue: "circle.lefthalf.filled"
        case .misleading: "exclamationmark.triangle.fill"
        case .mostlyFalse, .false_: "xmark.circle.fill"
        case .unverified: "questionmark.circle.fill"
        case .notCheckable: "text.bubble.fill"
        }
    }
}

extension Stance {
    var color: Color {
        switch self {
        case .supports: .green
        case .contradicts: .red
        case .context: .secondary
        }
    }

    var label: String {
        switch self {
        case .supports: "Supports"
        case .contradicts: "Contradicts"
        case .context: "Context"
        }
    }

    var symbol: String {
        switch self {
        case .supports: "checkmark.circle.fill"
        case .contradicts: "xmark.circle.fill"
        case .context: "info.circle.fill"
        }
    }
}

/// Fact checks are the one feature that can't run without a cloud model: it must search the web for evidence.
struct KeyRequiredCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Fact checks need an API key", systemImage: "key.fill").font(.headline)
            Text("Checking a claim means searching the web for independent sources and weighing them, which takes a cloud model. TruthLens uses your own Anthropic API key for that, and bills nothing itself. Everything else works without one: file checks, History, Stats, audio, and replies written on this device.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { app.showSettings = true } label: {
                Label("Add an API key", systemImage: "key.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct FactCheckView: View {
    @Environment(AppModel.self) private var app
    private var model: FactCheckModel { app.factCheck }
    @State private var pickerItem: PhotosPickerItem?
    @State private var importing = false
    @State private var showReply = false
    @State private var showNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    switch model.phase {
                    case .idle, .failed:
                        if !app.hasKey { KeyRequiredCard() }
                        inputCard
                        if case .failed(let message) = model.phase { ErrorCard(message: message) }
                    case .checking:
                        inputCard
                        CheckingCard(status: model.status) { model.cancel() }
                    case .done(let report):
                        FactCheckReportView(report: report, model: model,
                                            onReply: { showReply = true }, onNote: { showNote = true })
                        if model.showsCost { CostNote(cost: app.usage.lastCost[.factCheck]) }
                    }
                    Text("Fact checks are drawn from web sources and can be wrong or out of date. Open the sources and judge for yourself.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Background())
            .navigationTitle("Fact Check")
            .toolbar {
                if model.fromHistory {
                    ToolbarItem(placement: .navigation) {
                        Button { app.tab = .history } label: { Label("History", systemImage: "chevron.backward") }
                            .accessibilityLabel("Back to History")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { app.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                if model.report != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("New check", systemImage: "arrow.counterclockwise") { model.reset() }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit", systemImage: "pencil") { model.edit() }
                    }
                } else if model.lastReport != nil && !model.isChecking {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back to results", systemImage: "chevron.backward") { model.backToResults() }
                    }
                }
            }
        }
        .sheet(isPresented: $showReply) {
            if let report = model.report {
                ReplySheet { platform, tone in
                    try await app.draftReply(for: report, platform: platform, tone: tone)
                }
            }
        }
        .sheet(isPresented: $showNote) {
            if let report = model.report { CommunityNoteSheet(report: report) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { model.attach(url: url) }
        }
        .onChange(of: pickerItem) { _, item in
            if let item { model.attach(pickerItem: item) }
        }
    }

    // MARK: Input

    private var inputCard: some View {
        @Bindable var model = app.factCheck
        return VStack(alignment: .leading, spacing: 14) {
            Label("What's the claim?", systemImage: "quote.opening").font(.headline)
            TextEditor(text: $model.claim)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if model.claim.isEmpty {
                        Text("Paste a statement or post, e.g. “Gas prices are down 20% this year.”")
                            .foregroundStyle(.tertiary).padding(.top, 16).padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Claim to fact-check")

            Group {
                TextField("Who said it / where (optional)", text: $model.speaker)
                TextField("Link to the post (optional)", text: $model.postURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
            }
            .textFieldStyle(.roundedBorder)

            screenshotRow

            VStack(alignment: .leading, spacing: 6) {
                Picker("Search depth", selection: $model.depth) {
                    ForEach(FactDepth.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(model.depth.blurb).font(.footnote).foregroundStyle(.secondary)
            }

            Button {
                model.check(using: app.client)
            } label: {
                Label("Check this claim", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!model.canCheck || model.isChecking || !app.hasKey)

            if model.lastReport != nil && !model.isChecking {
                Button { model.backToResults() } label: {
                    Label("Back to previous results", systemImage: "chevron.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .card()
    }

    private var screenshotRow: some View {
        HStack(spacing: 12) {
            if let data = model.screenshot, let image = Image(data: data) {
                image.resizable().scaledToFill().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Screenshot attached").font(.subheadline)
                Spacer()
                Button("Remove", systemImage: "xmark.circle") { model.screenshot = nil }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
            } else {
                Text("Or attach a screenshot of the post").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Photos", systemImage: "photo") }
                Button { importing = true } label: { Label("Files", systemImage: "folder") }
                #if os(macOS)
                Button { if let d = Clipboard.imageData() { model.attach(imageData: d) } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                #endif
            }
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Result

struct FactCheckReportView: View {
    let report: FactCheckReport
    let model: FactCheckModel
    let onReply: () -> Void
    let onNote: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            banner
            explanation
            if !report.evidence.isEmpty { evidence }
            if !report.sources.isEmpty { sources }
            if let caveats = report.caveats, !caveats.isEmpty {
                Label(caveats, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
            FollowUpSection(model: model)
            Button(action: onReply) {
                Label("Draft a reply", systemImage: "arrowshape.turn.up.left.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            if !report.sources.isEmpty && report.rating != .notCheckable {
                Button(action: onNote) {
                    Label("Draft a Community Note", systemImage: "person.3.sequence.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: report.rating.symbol).font(.title)
                Text(report.rating.title.uppercased()).font(.title2.weight(.heavy))
            }
            .foregroundStyle(report.rating.color)
            .accessibilityElement(children: .combine)
            Text("“\(report.claim)”").font(.subheadline.italic()).foregroundStyle(.secondary)
            Text(report.headline).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(report.rating.color.opacity(0.6), lineWidth: 2)
        )
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why").font(.headline)
            Text(report.explanation).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Key evidence").font(.headline)
            ForEach(report.evidence) { point in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: point.stance.symbol).foregroundStyle(point.stance.color)
                        .accessibilityLabel(point.stance.label)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.title).font(.subheadline.bold())
                        Text(point.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sources", systemImage: "books.vertical.fill").font(.headline)
            ForEach(report.sources) { src in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(src.stance.label).font(.caption.bold()).foregroundStyle(src.stance.color)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(src.stance.color.opacity(0.15), in: Capsule())
                        Text(src.publisher).font(.caption).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: src.url) {
                        Link(destination: url) {
                            Text(src.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(src.title).font(.subheadline.weight(.semibold))
                    }
                    Text(src.finding).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}


// MARK: - Progress

struct CheckingCard: View {
    let status: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
            Text(status).font(.subheadline.weight(.medium)).lineLimit(2)
                .accessibilityLabel("Fact check in progress: \(status)")
            Spacer()
            Button("Cancel", action: onCancel).buttonStyle(.bordered)
        }
        .card()
    }
}

// MARK: - Follow-ups and challenges

struct FollowUpSection: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: FactCheckModel

    private let suggestions = [
        "What's the strongest counterargument?",
        "Is there newer data?",
        "Explain it simply",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ask a follow-up or challenge this", systemImage: "bubble.left.and.text.bubble.right")
                .font(.headline)

            ForEach(model.thread) { exchange in
                ExchangeView(exchange: exchange) { model.applyRevision(from: exchange.id) }
            }

            if model.thread.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { text in
                            Button(text) { model.ask(text, using: app) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("e.g. “But I read that prices are up 5%…”", text: $model.followUpText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask(model.followUpText, using: app) }
                Button {
                    model.ask(model.followUpText, using: app)
                } label: {
                    Label("Ask", systemImage: "arrow.up.circle.fill").labelStyle(.iconOnly).font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(model.followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAsking || app.followUpEngine == .none)
                .accessibilityLabel("Ask")
            }
            Group {
                switch app.followUpEngine {
                case .claude:
                    Text("Challenges are fact-checked, not taken on faith. The rating only changes if verified sources support it.")
                case .onDevice:
                    Text("Answered on this device from this result only. It can't search the web, so it can't verify new claims. Add an API key to check challenges against sources.")
                case .none:
                    Text("Follow-ups need an Anthropic API key or Apple Intelligence.")
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ExchangeView: View {
    let exchange: FactCheckModel.Exchange
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exchange.question)
                .font(.subheadline.weight(.semibold))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            switch exchange.state {
            case .asking(let status):
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(status).font(.footnote).lineLimit(2) }
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
            case .answered(let answer):
                Text(answer.answer).font(.subheadline)
                ForEach(answer.sources) { src in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(src.stance.label).font(.caption.bold()).foregroundStyle(src.stance.color)
                            Text(src.publisher).font(.caption).foregroundStyle(.secondary)
                        }
                        if let url = URL(string: src.url) {
                            Link(src.title, destination: url).font(.footnote.weight(.semibold))
                        }
                        Text(src.finding).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let revision = answer.revision { revisionCard(revision) }
            }
        }
    }

    private func revisionCard(_ revision: Revision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Suggested revision: \(revision.rating.title)", systemImage: revision.rating.symbol)
                .font(.subheadline.bold()).foregroundStyle(revision.rating.color)
            Text(revision.reason).font(.footnote)
            if exchange.applied {
                Label("Applied", systemImage: "checkmark").font(.footnote.bold()).foregroundStyle(.green)
            } else {
                Button("Apply revision", action: onApply).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(revision.rating.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
