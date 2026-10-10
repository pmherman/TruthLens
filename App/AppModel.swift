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

@MainActor @Observable
final class AppModel {
    enum Phase { case idle, analyzing(String), done(AnalysisReport), failed(String) }

    var phase: Phase = .idle
    var previewData: Data?
    var previewKind: MediaKind = .image
    var postText = ""
    var postURL = ""
    var apiKey: String = Keychain.load() ?? "" {
        didSet { Keychain.save(apiKey) }
    }
    var showSettings = false

    private var lastPrepared: PreparedMedia?
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

    /// Re-run with the current post text / URL (e.g. after the user adds context).
    func reanalyze() {
        guard let prepared = lastPrepared else { return }
        analyze(prepared)
    }

    func reset() {
        task?.cancel()
        phase = .idle
        previewData = nil
        lastPrepared = nil
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
        lastPrepared = prepared
        previewData = prepared.frames.first
        previewKind = prepared.kind
        phase = .analyzing("Scanning and fact-checking…")
        let ctx = UserContext(postText: postText, postURL: postURL)
        let client = client
        task?.cancel()
        task = Task {
            do {
                let report = try await client.analyze(prepared, context: ctx)
                if !Task.isCancelled { phase = .done(report) }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
