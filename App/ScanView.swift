import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import TruthLensCore

struct ScanView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var importing = false
    @State private var targeted = false
    @State private var showReply = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dropZone
                    switch model.phase {
                    case .idle: EmptyView()
                    case .analyzing(let status): ProgressCard(status: status)
                    case .failed(let message): ErrorCard(message: message)
                    case .done(let report):
                        ReportView(report: report) { showReply = true }
                        if report.isMetadataOnly && model.previewKind != .audio { MetadataOnlyCard() }
                        if model.showsScanCost { CostNote(cost: model.usage.lastCost[.scan]) }
                    }
                    Text("AI detection is probabilistic. Treat results as evidence, not proof.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Background())
            .navigationTitle("AI Scan")
            .toolbar {
                if model.scanFromHistory {
                    ToolbarItem(placement: .navigation) {
                        Button { model.tab = .history } label: { Label("History", systemImage: "chevron.backward") }
                            .accessibilityLabel("Back to History")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                if model.report != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("New scan", systemImage: "arrow.counterclockwise") { model.reset() }
                    }
                }
            }
        }
        .sheet(isPresented: $showReply) {
            if let report = model.report {
                ReplySheet { platform, tone in
                    try await model.draftReply(for: report, platform: platform, tone: tone)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie, .audio]) { result in
            if case .success(let url) = result { model.load(url: url) }
        }
        .onChange(of: pickerItem) { _, item in
            if let item { model.load(pickerItem: item) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            model.load(url: url)
            return true
        } isTargeted: { targeted = $0 }
    }

    // MARK: Pieces

    private var dropZone: some View {
        VStack(spacing: 16) {
            if let data = model.previewData, let image = Image(data: data) {
                image.resizable().scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if model.previewKind == .video {
                            Image(systemName: "play.circle.fill").font(.title).padding(10)
                                .foregroundStyle(.white).shadow(radius: 4)
                        }
                    }
            } else {
                Image(systemName: model.previewKind == .audio && model.previewData == nil && model.report != nil
                      ? "waveform" : "sparkle.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("Drop a photo, video or audio file").font(.headline)
                Text("or choose one below. The scan starts instantly.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                Button { importing = true } label: { Label("Files", systemImage: "folder") }
                #if os(macOS)
                Button { if let d = Clipboard.imageData() { model.load(imageData: d) } } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                #endif
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : .primary.opacity(0.08),
                              style: StrokeStyle(lineWidth: targeted ? 3 : 1, dash: targeted ? [8] : []))
        )
        .animation(.snappy, value: targeted)
    }

}

struct Background: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.purple.opacity(0.08), .clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct ProgressCard: View {
    let status: String
    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
            Text(status).font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ErrorCard: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Shown under a metadata-only result: says what was and wasn't checked, and how to get the full analysis.
struct MetadataOnlyCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("File check only", systemImage: "doc.text.magnifyingglass").font(.headline)
            Text(app.hasKey
                 ? "Visual analysis is off for this scan, so only the file's metadata was checked on this device. Run it to have Claude inspect the pixels. This sends the image to Anthropic."
                 : "Only the file's metadata was checked, on this device and for free. A visual analysis by Claude can inspect the pixels for generation tells, but it needs an Anthropic API key.")
                .font(.subheadline).foregroundStyle(.secondary)
            if app.hasKey {
                if app.canRunVisualAnalysis {
                    Button { app.runVisualAnalysis() } label: {
                        Label("Run visual analysis", systemImage: "eye").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            } else {
                Button { app.showSettings = true } label: {
                    Label("Add an API key", systemImage: "key.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
