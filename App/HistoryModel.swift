import SwiftUI
import TruthLensCore

@MainActor @Observable
final class HistoryModel {
    private let storage: HistoryStorage
    private(set) var entries: [HistoryEntry] = []
    private(set) var totalBytes = 0

    /// Thumbnails are small and lossy on purpose: enough to recognise the item, cheap to keep.
    private static let scanThumbPixels = 480
    private static let screenshotThumbPixels = 1000   // text in a screenshot needs more pixels to stay legible

    init(storage: HistoryStorage = HistoryStorage(root: HistoryStorage.defaultRoot)) {
        self.storage = storage
        reload()
    }

    /// User setting: whether new scans and checks are saved at all.
    var savingEnabled: Bool {
        UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? true
    }

    var protectedCount: Int { entries.filter(\.protected).count }
    var clearable: [HistoryEntry] { HistoryPolicy.clearable(entries) }
    var clearableBytes: Int { storage.bytes(of: clearable.map(\.id)) }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func entry(_ id: UUID) -> HistoryEntry? { entries.first { $0.id == id } }
    func thumbnail(for id: UUID) -> Data? { storage.thumbnail(for: id) }

    // MARK: Recording

    func recordScan(report: AnalysisReport, kind: MediaKind, image: Data?) {
        guard savingEnabled else { return }
        let thumb = image.flatMap { MediaPreparer.thumbnail(from: $0, maxPixel: Self.scanThumbPixels) }
        let entry = HistoryEntry(kind: .scan, hasThumbnail: thumb != nil,
                                 scan: ScanRecord(mediaKind: kind, report: report))
        insert(entry, thumbnail: thumb)
    }

    /// Returns the new entry's id so later follow-ups can be saved onto it.
    @discardableResult
    func recordFact(claim: String, speaker: String, url: String, depth: FactDepth,
                    report: FactCheckReport, screenshot: Data?) -> UUID? {
        guard savingEnabled else { return nil }
        let thumb = screenshot.flatMap { MediaPreparer.thumbnail(from: $0, maxPixel: Self.screenshotThumbPixels) }
        let entry = HistoryEntry(kind: .factCheck, hasThumbnail: thumb != nil,
                                 fact: FactRecord(claim: claim, speaker: speaker, url: url,
                                                  depth: depth.rawValue, report: report))
        insert(entry, thumbnail: thumb)
        return entry.id
    }

    /// Saves the current result and follow-up thread back onto an existing fact check.
    func updateFact(id: UUID, report: FactCheckReport, thread: [StoredFollowUp]) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].fact?.report = report
        entries[i].fact?.thread = thread
        try? storage.save(entries[i])
        totalBytes = storage.totalBytes()
    }

    private func insert(_ entry: HistoryEntry, thumbnail: Data?) {
        guard (try? storage.save(entry, thumbnail: thumbnail)) != nil else { return }
        entries.insert(entry, at: 0)
        totalBytes = storage.totalBytes()
    }

    // MARK: Protect and delete

    func setProtected(_ ids: Set<UUID>, _ value: Bool) {
        for i in entries.indices where ids.contains(entries[i].id) && entries[i].protected != value {
            entries[i].protected = value
            try? storage.save(entries[i])
        }
    }

    /// Deletes exactly these entries, protected or not. Callers decide what's allowed.
    func delete(_ ids: [UUID]) {
        storage.delete(ids)
        let gone = Set(ids)
        entries.removeAll { gone.contains($0.id) }
        totalBytes = storage.totalBytes()
    }

    /// Bulk delete from a selection. Protected items are never touched. Returns how many were kept.
    @discardableResult
    func deleteSelection(_ selection: Set<UUID>) -> Int {
        let split = HistoryPolicy.split(selection: selection, in: entries)
        delete(split.deletable)
        return split.keptProtected
    }

    func clearUnprotected() { delete(clearable.map(\.id)) }

    func clearAll() { delete(entries.map(\.id)) }

    private func reload() {
        entries = storage.loadAll()
        totalBytes = storage.totalBytes()
    }
}
