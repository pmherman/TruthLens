import SwiftUI
import PhotosUI
import TruthLensCore

@MainActor @Observable
final class FactCheckModel {
    enum Phase { case idle, checking, done(FactCheckReport), failed(String) }

    var phase: Phase = .idle
    var claim = ""
    var speaker = ""
    var postURL = ""
    var screenshot: Data?

    private var task: Task<Void, Never>?

    var report: FactCheckReport? { if case .done(let r) = phase { r } else { nil } }
    var isChecking: Bool { if case .checking = phase { true } else { false } }
    var canCheck: Bool {
        !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || screenshot != nil
    }

    func check(using client: ClaudeClient) {
        guard canCheck else { return }
        task?.cancel()
        phase = .checking
        let (claim, speaker, url, shot) = (claim, speaker, postURL.trimmingCharacters(in: .whitespacesAndNewlines), screenshot)
        task = Task {
            do {
                let report = try await client.factCheck(claim: claim, speaker: speaker, url: url, screenshot: shot)
                if !Task.isCancelled { phase = .done(report) }
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    func attach(imageData: Data) {
        Task {
            do {
                screenshot = try await MediaPreparer.prepare(data: imageData, kind: .image).frames.first
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func attach(pickerItem: PhotosPickerItem) {
        Task {
            if let data = try? await pickerItem.loadTransferable(type: Data.self) { attach(imageData: data) }
        }
    }

    func attach(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) { attach(imageData: data) }
    }

    /// Back to an empty form.
    func reset() {
        task?.cancel()
        phase = .idle
        claim = ""; speaker = ""; postURL = ""; screenshot = nil
    }

    /// Back to the form with the inputs kept, to tweak and re-check.
    func edit() {
        task?.cancel()
        phase = .idle
    }
}
