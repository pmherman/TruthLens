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

struct FactCheckView: View {
    @Environment(AppModel.self) private var app
    @State private var model = FactCheckModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var importing = false
    @State private var showReply = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    switch model.phase {
                    case .idle, .failed:
                        inputCard
                        if case .failed(let message) = model.phase { ErrorCard(message: message) }
                    case .checking:
                        inputCard
                        ProgressCard(status: "Searching independent sources…")
                    case .done(let report):
                        FactCheckReportView(report: report, onReply: { showReply = true })
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
                }
            }
        }
        .sheet(isPresented: $showReply) {
            if let report = model.report {
                ReplySheet { platform, tone in
                    try await app.client.draftReply(for: report, platform: platform, tone: tone)
                }
            }
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
        @Bindable var model = model
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

            Button {
                model.check(using: app.client)
            } label: {
                Label("Check this claim", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!model.canCheck || model.isChecking)
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
    let onReply: () -> Void

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
            Button(action: onReply) {
                Label("Draft a reply", systemImage: "arrowshape.turn.up.left.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
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
