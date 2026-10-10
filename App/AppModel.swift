import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import TruthLensCore

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum AppTab: Hashable { case scan, factCheck, history, stats }

/// What writes drafts (replies, notes) right now.
enum WritingEngine {
    case claude, onDevice, none

    var label: String {
        switch self {
        case .claude: "Written by Claude (uses your API key)"
        case .onDevice: "Written on this device: free and private, but check the facts before posting"
        case .none: "Unavailable"
        }
    }
}

enum WritingError: LocalizedError {
    case noEngine
    var errorDescription: String? {
        "Add an Anthropic API key in Settings, or turn on Apple Intelligence (macOS 26 / iOS 26 or later), to draft text."
    }
}

@MainActor @Observable
final class AppModel {
    enum Phase { case idle, analyzing(String), done(AnalysisReport), failed(String) }

    var phase: Phase = .idle
    var previewData: Data?
    var previewKind: MediaKind = .image
    var apiKey: String = Keychain.load() ?? "" {
        didSet { Keychain.save(apiKey) }
    }
    var showSettings = false

    /// Use the free on-device model for replies and notes even when an API key is set.
    var preferOnDevice = UserDefaults.standard.bool(forKey: "preferOnDevice") {
        didSet { UserDefaults.standard.set(preferOnDevice, forKey: "preferOnDevice") }
    }
    /// Send images to Claude for visual analysis (needs a key). Off keeps scans to on-device file checks.
    var cloudScan = UserDefaults.standard.object(forKey: "cloudScan") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cloudScan, forKey: "cloudScan") }
    }
    private(set) var onDevice = OnDevice.status
    private let localWriter = OnDeviceWriter()
    private var lastPrepared: PreparedMedia?

    var tab: AppTab = .scan {
        didSet { if tab == .history { scanFromHistory = false; factCheck.fromHistory = false } }
    }
    /// True while a scan reopened from History is on screen, so the view can offer a way back to the list.
    var scanFromHistory = false

    let history = HistoryModel()
    let usage = UsageTracker()
    let factCheck = FactCheckModel()
    var showsScanCost = false

    init() {
        factCheck.history = history
        factCheck.usage = usage
    }

    private var task: Task<Void, Never>?

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var report: AnalysisReport? { if case .done(let r) = phase { r } else { nil } }
    /// A client that reports every call's token and search usage to the tracker.
    var client: ClaudeClient {
        var c = ClaudeClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        c.usageSink = { [usage] kind, used, model in
            Task { @MainActor in usage.record(kind: kind, usage: used, model: model) }
        }
        return c
    }

    func refreshOnDevice() { onDevice = OnDevice.status }

    /// Replies and notes: on-device when preferred or when there's no key, Claude otherwise.
    var writingEngine: WritingEngine {
        if preferOnDevice && onDevice.isAvailable { return .onDevice }
        if hasKey { return .claude }
        return onDevice.isAvailable ? .onDevice : .none
    }

    /// Follow-ups: Claude whenever there's a key, because only it can verify a challenge against sources.
    var followUpEngine: WritingEngine {
        hasKey ? .claude : (onDevice.isAvailable ? .onDevice : .none)
    }

    /// Rates shown to the user, for the model the app calls.
    var pricing: ModelPricing { ModelPricing.forModel(client.model) }

    // MARK: Drafting (routes to Claude or the on-device model)

    func draftReply(for report: AnalysisReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        switch writingEngine {
        case .claude: try await client.draftReply(for: report, platform: platform, tone: tone)
        case .onDevice: try await localWriter.draftReply(for: report, platform: platform, tone: tone)
        case .none: throw WritingError.noEngine
        }
    }

    func draftReply(for report: FactCheckReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        switch writingEngine {
        case .claude: try await client.draftReply(for: report, platform: platform, tone: tone)
        case .onDevice: try await localWriter.draftReply(for: report, platform: platform, tone: tone)
        case .none: throw WritingError.noEngine
        }
    }

    func draftCommunityNote(for report: FactCheckReport, source: FactSource) async throws -> String {
        switch writingEngine {
        case .claude: try await client.draftCommunityNote(for: report, source: source)
        case .onDevice: try await localWriter.draftCommunityNote(for: report, source: source)
        case .none: throw WritingError.noEngine
        }
    }

    func followUp(question: String, report: FactCheckReport, history: [FollowUpTurn],
                  onProgress: @escaping @Sendable (SearchProgress) -> Void) async throws -> FollowUpAnswer {
        switch followUpEngine {
        case .claude: try await client.followUp(question: question, report: report, history: history, onProgress: onProgress)
        case .onDevice: try await localWriter.followUp(question: question, report: report, history: history)
        case .none: throw WritingError.noEngine
        }
    }

    // MARK: Intake

    func load(pickerItem: PhotosPickerItem) {
        run("Reading…") {
            if let movie = try await pickerItem.loadTransferable(type: PickedMovie.self) {
                return try await MediaPreparer.prepare(url: movie.url)
            }
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else { throw MediaError.unreadable }
            return try await MediaPreparer.prepare(data: data, kind: .image)
        }
    }

    func load(url: URL) {
        run("Reading…") { try await MediaPreparer.prepare(url: url) }
    }

    func load(imageData: Data) {
        run("Reading…") { try await MediaPreparer.prepare(data: imageData, kind: .image) }
    }

    func reset() {
        scanFromHistory = false
        lastPrepared = nil
        task?.cancel()
        phase = .idle
        previewData = nil
    }

    // MARK: Pipeline

    private func run(_ status: String, _ prepare: @escaping @Sendable () async throws -> PreparedMedia) {
        scanFromHistory = false
        task?.cancel()
        phase = .analyzing(status)
        task = Task {
            do {
                let prepared = try await prepare()
                analyze(prepared)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Scans with Claude when there's a key (and cloud scanning is on); otherwise runs the on-device file checks only.
    private func analyze(_ prepared: PreparedMedia, forceCloud: Bool = false) {
        lastPrepared = prepared
        previewData = prepared.frames.first
        previewKind = prepared.kind
        showsScanCost = false
        task?.cancel()

        guard hasKey && (cloudScan || forceCloud) else {
            finishScan(MetadataReport.make(signals: prepared.signals, kind: prepared.kind), prepared, billable: false)
            return
        }
        phase = .analyzing("Scanning…")
        let client = client
        task = Task {
            do {
                let report = try await client.analyze(prepared)
                if !Task.isCancelled { finishScan(report, prepared, billable: true) }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func finishScan(_ report: AnalysisReport, _ prepared: PreparedMedia, billable: Bool) {
        phase = .done(report)
        let id = history.recordScan(report: report, kind: prepared.kind, image: prepared.frames.first) ?? UUID()
        usage.recordCheck(id: id, kind: .scan, outcome: report.verdict.rawValue)
        showsScanCost = billable
    }

    /// Re-runs the current file with Claude's visual analysis, e.g. after adding an API key.
    func runVisualAnalysis() {
        guard hasKey else { showSettings = true; return }
        guard let prepared = lastPrepared else { return }
        analyze(prepared, forceCloud: true)
    }

    var canRunVisualAnalysis: Bool { lastPrepared != nil }

    // MARK: History

    /// Reopens a saved scan or fact check in its own tab.
    func open(_ entry: HistoryEntry) {
        switch entry.kind {
        case .scan:
            guard let scan = entry.scan else { return }
            task?.cancel()
            showsScanCost = false
            scanFromHistory = true
            previewData = history.thumbnail(for: entry.id)
            previewKind = scan.mediaKind
            phase = .done(scan.report)
            tab = .scan
        case .factCheck:
            factCheck.restore(entry, thumbnail: history.thumbnail(for: entry.id))
            tab = .factCheck
        }
    }
}
