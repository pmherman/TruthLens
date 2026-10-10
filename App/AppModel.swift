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

enum AppTab: Hashable { case scan, factCheck, history }

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
    var tab: AppTab = .scan

    let history = HistoryModel()
    let factCheck = FactCheckModel()

    init() { factCheck.history = history }

    private var task: Task<Void, Never>?

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var report: AnalysisReport? { if case .done(let r) = phase { r } else { nil } }
    var client: ClaudeClient { ClaudeClient(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }

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
        task?.cancel()
        phase = .idle
        previewData = nil
    }

    // MARK: Pipeline

    private func run(_ status: String, _ prepare: @escaping @Sendable () async throws -> PreparedMedia) {
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

    private func analyze(_ prepared: PreparedMedia) {
        guard hasKey else {
            phase = .failed(ClaudeError.missingKey.localizedDescription)
            showSettings = true
            return
        }
        previewData = prepared.frames.first
        previewKind = prepared.kind
        phase = .analyzing("Scanning…")
        let client = client
        task?.cancel()
        task = Task {
            do {
                let report = try await client.analyze(prepared)
                if !Task.isCancelled {
                    phase = .done(report)
                    history.recordScan(report: report, kind: prepared.kind, image: prepared.frames.first)
                }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: History

    /// Reopens a saved scan or fact check in its own tab.
    func open(_ entry: HistoryEntry) {
        switch entry.kind {
        case .scan:
            guard let scan = entry.scan else { return }
            task?.cancel()
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
