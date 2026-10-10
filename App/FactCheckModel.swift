import SwiftUI
import PhotosUI
import TruthLensCore

@MainActor @Observable
final class FactCheckModel {
    enum Phase { case idle, checking, done(FactCheckReport), failed(String) }

    /// One question in the follow-up thread.
    struct Exchange: Identifiable {
        enum State { case asking(String), answered(FollowUpAnswer), failed(String) }
        let id = UUID()
        let question: String
        var state: State
        var applied = false
    }


    var phase: Phase = .idle
    var status = ""
    var claim = ""
    var speaker = ""
    var postURL = ""
    var screenshot: Data?
    var depth: FactDepth = FactDepth(rawValue: UserDefaults.standard.string(forKey: "factDepth") ?? "") ?? .standard {
        didSet { UserDefaults.standard.set(depth.rawValue, forKey: "factDepth") }
    }

    /// The last finished result, kept while editing so "Back to results" never costs another search.
    private(set) var lastReport: FactCheckReport?
    var thread: [Exchange] = []
    var followUpText = ""

    /// Where finished checks and their follow-ups are saved. Set by `AppModel`.
    var history: HistoryModel?
    private var entryID: UUID?

    private var task: Task<Void, Never>?
    private var followTask: Task<Void, Never>?

    var report: FactCheckReport? { if case .done(let r) = phase { r } else { nil } }
    var isChecking: Bool { if case .checking = phase { true } else { false } }
    var isAsking: Bool { thread.contains { if case .asking = $0.state { true } else { false } } }
    var canCheck: Bool {
        !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || screenshot != nil
    }

    static func describe(_ p: SearchProgress) -> String {
        switch p {
        case .searching(let q): "Searching: \(q)"
        case .reading(let n): "Reading \(n) result\(n == 1 ? "" : "s")…"
        case .writing: "Writing up the verdict…"
        }
    }

    // MARK: Checking

    func check(using client: ClaudeClient) {
        guard canCheck else { return }
        task?.cancel()
        phase = .checking
        status = "Starting…"
        let (claim, speaker, url, shot, depth) =
            (claim, speaker, postURL.trimmingCharacters(in: .whitespacesAndNewlines), screenshot, depth)
        task = Task {
            do {
                let report = try await client.factCheck(claim: claim, speaker: speaker, url: url,
                                                        screenshot: shot, depth: depth) { [weak self] progress in
                    Task { @MainActor in self?.status = Self.describe(progress) }
                }
                if Task.isCancelled { return }
                followTask?.cancel()
                thread = []
                lastReport = report
                phase = .done(report)
                entryID = history?.recordFact(claim: claim, speaker: speaker, url: url, depth: depth,
                                              report: report, screenshot: shot)
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Stops a running check and returns to wherever the user was.
    func cancel() {
        task?.cancel()
        phase = lastReport.map { .done($0) } ?? .idle
    }

    /// Back to the form with the inputs kept. The result stays available via `backToResults()`.
    func edit() {
        task?.cancel()
        phase = .idle
    }

    func backToResults() {
        guard let lastReport else { return }
        phase = .done(lastReport)
    }

    /// Back to an empty form.
    func reset() {
        task?.cancel(); followTask?.cancel()
        phase = .idle
        lastReport = nil
        entryID = nil
        thread = []
        followUpText = ""
        claim = ""; speaker = ""; postURL = ""; screenshot = nil
    }

    // MARK: Follow-ups and challenges

    func ask(_ question: String, using client: ClaudeClient) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let report, !q.isEmpty, !isAsking else { return }
        followUpText = ""
        let exchange = Exchange(question: q, state: .asking("Thinking…"))
        let id = exchange.id
        let history = thread.compactMap { ex -> FollowUpTurn? in
            if case .answered(let a) = ex.state { FollowUpTurn(question: ex.question, answer: a.answer) } else { nil }
        }
        thread.append(exchange)
        followTask = Task {
            do {
                let answer = try await client.followUp(question: q, report: report, history: history) { [weak self] progress in
                    Task { @MainActor in self?.setState(id, .asking(Self.describe(progress))) }
                }
                if !Task.isCancelled { setState(id, .answered(answer)); persist() }
            } catch {
                if !Task.isCancelled { setState(id, .failed(error.localizedDescription)) }
            }
        }
    }

    private func setState(_ id: UUID, _ state: Exchange.State) {
        guard let i = thread.firstIndex(where: { $0.id == id }) else { return }
        thread[i].state = state
    }

    /// Applies a revision the user accepted: new rating, headline and any newly found sources.
    func applyRevision(from id: UUID) {
        guard let i = thread.firstIndex(where: { $0.id == id }), !thread[i].applied,
              case .answered(let answer) = thread[i].state, let revision = answer.revision,
              let report else { return }
        let updated = report.applying(revision, newSources: answer.sources)
        thread[i].applied = true
        lastReport = updated
        phase = .done(updated)
        persist()
    }

    /// Saves the current result and answered follow-ups onto this check's history entry.
    private func persist() {
        guard let entryID, let current = lastReport else { return }
        let stored = thread.compactMap { ex -> StoredFollowUp? in
            if case .answered(let a) = ex.state { StoredFollowUp(question: ex.question, answer: a, applied: ex.applied) } else { nil }
        }
        history?.updateFact(id: entryID, report: current, thread: stored)
    }

    // MARK: Restoring from history

    /// Reopens a saved fact check with its inputs, result and follow-up thread.
    func restore(_ entry: HistoryEntry, thumbnail: Data?) {
        guard let fact = entry.fact else { return }
        task?.cancel(); followTask?.cancel()
        claim = fact.claim; speaker = fact.speaker; postURL = fact.url
        depth = FactDepth(rawValue: fact.depth) ?? depth
        screenshot = thumbnail
        thread = fact.thread.map { Exchange(question: $0.question, state: .answered($0.answer), applied: $0.applied) }
        followUpText = ""
        lastReport = fact.report
        entryID = entry.id
        phase = .done(fact.report)
    }

    // MARK: Screenshot

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
}
