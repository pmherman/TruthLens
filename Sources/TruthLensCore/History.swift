import Foundation

// MARK: - Records

/// An answered follow-up, as saved with a fact check.
public struct StoredFollowUp: Codable, Sendable {
    public let question: String
    public let answer: FollowUpAnswer
    public let applied: Bool
    public init(question: String, answer: FollowUpAnswer, applied: Bool) {
        self.question = question; self.answer = answer; self.applied = applied
    }
}

public struct ScanRecord: Codable, Sendable {
    public let mediaKind: MediaKind
    public let report: AnalysisReport
    public init(mediaKind: MediaKind, report: AnalysisReport) { self.mediaKind = mediaKind; self.report = report }
}

public struct FactRecord: Codable, Sendable {
    public var claim: String
    public var speaker: String
    public var url: String
    public var depth: String
    public var report: FactCheckReport
    public var thread: [StoredFollowUp]
    public init(claim: String, speaker: String, url: String, depth: String,
                report: FactCheckReport, thread: [StoredFollowUp] = []) {
        self.claim = claim; self.speaker = speaker; self.url = url; self.depth = depth
        self.report = report; self.thread = thread
    }
}

/// One saved AI scan or fact check.
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case scan, factCheck }

    public let id: UUID
    public var date: Date
    public var kind: Kind
    /// Protected entries survive "clear history" and bulk deletes.
    public var protected: Bool
    public var hasThumbnail: Bool
    public var scan: ScanRecord?
    public var fact: FactRecord?

    public init(id: UUID = UUID(), date: Date = .now, kind: Kind, protected: Bool = false,
                hasThumbnail: Bool, scan: ScanRecord? = nil, fact: FactRecord? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.protected = protected
        self.hasThumbnail = hasThumbnail; self.scan = scan; self.fact = fact
    }

    public var title: String {
        switch kind {
        case .scan: scan?.report.headline ?? "AI scan"
        case .factCheck: fact?.report.claim ?? "Fact check"
        }
    }

    /// Short result label, e.g. "Likely AI · 82" or "Partially true".
    public var badge: String {
        switch kind {
        case .scan: scan.map { "\($0.report.verdict.title) · \($0.report.aiScore)" } ?? ""
        case .factCheck: fact?.report.rating.title ?? ""
        }
    }

    /// Lower-cased text the history search matches against.
    public var searchText: String {
        switch kind {
        case .scan:
            guard let r = scan?.report else { return "" }
            return ([r.headline, r.verdict.title] + r.reasons.map(\.title)).joined(separator: " ").lowercased()
        case .factCheck:
            guard let f = fact else { return "" }
            return [f.claim, f.speaker, f.url, f.report.claim, f.report.headline, f.report.rating.title]
                .joined(separator: " ").lowercased()
        }
    }
}

// MARK: - Rules

public enum HistoryPolicy {
    /// What "Clear history" removes: everything that isn't protected.
    public static func clearable(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.filter { !$0.protected }
    }

    /// Splits a bulk selection into what can be deleted and how many protected items are kept.
    public static func split(selection: Set<UUID>, in entries: [HistoryEntry]) -> (deletable: [UUID], keptProtected: Int) {
        let chosen = entries.filter { selection.contains($0.id) }
        return (chosen.filter { !$0.protected }.map(\.id), chosen.filter(\.protected).count)
    }
}

// MARK: - Storage

/// Each entry lives in its own folder: `item.json` plus an optional reduced-quality `thumb.jpg`.
/// That makes size accounting and deletion exact and keeps one corrupt item from affecting the rest.
public struct HistoryStorage: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TruthLens", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func itemURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("item.json") }
    private func thumbURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("thumb.jpg") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Writes the entry. A nil `thumbnail` leaves any existing thumbnail untouched.
    public func save(_ entry: HistoryEntry, thumbnail: Data? = nil) throws {
        try FileManager.default.createDirectory(at: folder(entry.id), withIntermediateDirectories: true)
        if let thumbnail { try thumbnail.write(to: thumbURL(entry.id), options: .atomic) }
        try encoder.encode(entry).write(to: itemURL(entry.id), options: .atomic)
    }

    /// Every readable entry, newest first. Unreadable folders are skipped.
    public func loadAll() -> [HistoryEntry] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("item.json")) else { return nil }
            return try? decoder.decode(HistoryEntry.self, from: data)
        }
        .sorted { $0.date > $1.date }
    }

    public func thumbnail(for id: UUID) -> Data? { try? Data(contentsOf: thumbURL(id)) }

    public func delete(_ ids: [UUID]) {
        for id in ids { try? FileManager.default.removeItem(at: folder(id)) }
    }

    /// Bytes on disk for one entry.
    public func bytes(of id: UUID) -> Int { Self.size(of: folder(id)) }

    public func bytes(of ids: [UUID]) -> Int { ids.reduce(0) { $0 + bytes(of: $1) } }

    public func totalBytes() -> Int { Self.size(of: root) }

    private static func size(of url: URL) -> Int {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in files {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
