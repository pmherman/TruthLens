import Foundation

// MARK: - Usage and pricing

/// What one API call consumed. `inputTokens` excludes cache reads/writes, which are billed at their own rates.
public struct APIUsage: Codable, Sendable, Equatable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0
    public var webSearches = 0

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0,
                cacheWriteTokens: Int = 0, webSearches: Int = 0) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens
        self.webSearches = webSearches
    }

    public var isEmpty: Bool { self == APIUsage() }
    public var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }

    /// Reads the `usage` object of a Messages API response or stream event. Missing fields stay at their current value.
    mutating func merge(_ json: [String: Any]?) {
        guard let json else { return }
        if let v = json["input_tokens"] as? Int { inputTokens = v }
        if let v = json["output_tokens"] as? Int { outputTokens = v }
        if let v = json["cache_read_input_tokens"] as? Int { cacheReadTokens = v }
        if let v = json["cache_creation_input_tokens"] as? Int { cacheWriteTokens = v }
        if let n = (json["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int { webSearches = n }
    }
}

/// Anthropic's published rates, in US dollars. Used for estimates only; the Anthropic Console has the exact bill.
public struct ModelPricing: Sendable, Equatable {
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheReadPerMTok: Double
    public let cacheWritePerMTok: Double   // 5-minute cache writes
    public let searchPer1000: Double

    /// Web search is billed per search on top of the tokens its results add.
    public static let webSearchPer1000 = 10.0

    public static func forModel(_ id: String) -> ModelPricing {
        switch id {
        case "claude-opus-5-5":
            ModelPricing(inputPerMTok: 4, outputPerMTok: 20, cacheReadPerMTok: 0.20, cacheWritePerMTok: 5, searchPer1000: webSearchPer1000)
        case "claude-sonnet-5":
            ModelPricing(inputPerMTok: 2, outputPerMTok: 10, cacheReadPerMTok: 0.20, cacheWritePerMTok: 2.50, searchPer1000: webSearchPer1000)
        case "claude-haiku-5-5":
            ModelPricing(inputPerMTok: 0.10, outputPerMTok: 0.50, cacheReadPerMTok: 0.01, cacheWritePerMTok: 0.125, searchPer1000: webSearchPer1000)
        default:   // claude-sonnet-5-5, the app's model, and the fallback for anything unknown
            ModelPricing(inputPerMTok: 2, outputPerMTok: 10, cacheReadPerMTok: 0.10, cacheWritePerMTok: 2.50, searchPer1000: webSearchPer1000)
        }
    }

    public func cost(_ u: APIUsage) -> Double {
        (Double(u.inputTokens) * inputPerMTok + Double(u.outputTokens) * outputPerMTok
         + Double(u.cacheReadTokens) * cacheReadPerMTok + Double(u.cacheWriteTokens) * cacheWritePerMTok) / 1_000_000
        + Double(u.webSearches) * searchPer1000 / 1_000
    }

    /// e.g. "$2 in / $10 out per million tokens, $10 per 1,000 searches"
    public var summary: String {
        "\(Money.rate(inputPerMTok)) in / \(Money.rate(outputPerMTok)) out per million tokens, "
        + "\(Money.rate(searchPer1000)) per 1,000 web searches"
    }
}

public enum Money {
    /// "$0.042" for small amounts, "$1.37" once it's a dollar or so. Never hides a non-zero amount as $0.00.
    public static func format(_ v: Double) -> String {
        if v <= 0 { return "$0.00" }
        if v < 0.001 { return "<$0.001" }
        return v < 0.1 ? String(format: "$%.3f", v) : String(format: "$%.2f", v)
    }

    static func rate(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v))" : String(format: "$%.2f", v)
    }
}

/// Which feature made an API call, so the cost breakdown can say where the money went.
public enum UsageKind: String, Codable, CaseIterable, Sendable {
    case scan, factCheck, followUp, reply, note

    public var title: String {
        switch self {
        case .scan: "AI scans"
        case .factCheck: "Fact checks"
        case .followUp: "Follow-ups"
        case .reply: "Reply drafts"
        case .note: "Community notes"
        }
    }
}

public struct UsageRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: UsageKind
    public let model: String
    public let usage: APIUsage
    public let cost: Double

    public init(id: UUID = UUID(), date: Date = .now, kind: UsageKind, model: String, usage: APIUsage) {
        self.id = id; self.date = date; self.kind = kind; self.model = model; self.usage = usage
        self.cost = ModelPricing.forModel(model).cost(usage)
    }
}

public struct UsageSummary: Sendable, Equatable {
    public var calls = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var searches = 0
    public var cost = 0.0
    public var averageCost: Double? { calls > 0 ? cost / Double(calls) : nil }
    public init() {}
}

public enum UsageStats {
    public static func summary(_ records: [UsageRecord], since: Date? = nil) -> UsageSummary {
        var s = UsageSummary()
        for r in records where since.map({ r.date >= $0 }) ?? true {
            s.calls += 1
            s.inputTokens += r.usage.inputTokens + r.usage.cacheReadTokens + r.usage.cacheWriteTokens
            s.outputTokens += r.usage.outputTokens
            s.searches += r.usage.webSearches
            s.cost += r.cost
        }
        return s
    }

    public static func summary(_ records: [UsageRecord], kind: UsageKind) -> UsageSummary {
        summary(records.filter { $0.kind == kind })
    }

    public static func startOfToday(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    public static func startOfMonth(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
    }
}

// MARK: - Result stats

/// A finished check, kept separately from History so the totals survive clearing history.
public struct CheckRecord: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case scan, factCheck }
    public let id: UUID
    public let date: Date
    public let kind: Kind
    /// `ClaimRating.rawValue` for fact checks, `Verdict.rawValue` for scans.
    public var outcome: String

    public init(id: UUID = UUID(), date: Date = .now, kind: Kind, outcome: String) {
        self.id = id; self.date = date; self.kind = kind; self.outcome = outcome
    }
}

/// Fact-check ratings grouped the way people think about them.
public enum FactBucket: String, CaseIterable, Sendable {
    case true_, mixed, false_, unclear

    public var title: String {
        switch self {
        case .true_: "True"
        case .mixed: "Mixed"
        case .false_: "False"
        case .unclear: "Unclear"
        }
    }

    public var blurb: String {
        switch self {
        case .true_: "True or mostly true"
        case .mixed: "Partially true or misleading"
        case .false_: "Mostly false or false"
        case .unclear: "Unverified or not a factual claim"
        }
    }

    public static func of(_ r: ClaimRating) -> FactBucket {
        switch r {
        case .true_, .mostlyTrue: .true_
        case .partiallyTrue, .misleading: .mixed
        case .mostlyFalse, .false_: .false_
        case .unverified, .notCheckable: .unclear
        }
    }
}

public enum ScanBucket: String, CaseIterable, Sendable {
    case ai, inconclusive, authentic

    public var title: String {
        switch self {
        case .ai: "AI-generated"
        case .inconclusive: "Inconclusive"
        case .authentic: "Authentic"
        }
    }

    public var blurb: String {
        switch self {
        case .ai: "AI-generated or likely AI"
        case .inconclusive: "Couldn't tell"
        case .authentic: "Authentic or likely authentic"
        }
    }

    public static func of(_ v: Verdict) -> ScanBucket {
        switch v {
        case .aiGenerated, .likelyAI: .ai
        case .uncertain: .inconclusive
        case .likelyAuthentic, .authentic: .authentic
        }
    }
}

public enum ResultStats {
    public static func factCounts(_ checks: [CheckRecord]) -> [ClaimRating: Int] {
        var out: [ClaimRating: Int] = [:]
        for c in checks where c.kind == .factCheck {
            if let r = ClaimRating(rawValue: c.outcome) { out[r, default: 0] += 1 }
        }
        return out
    }

    public static func factBuckets(_ checks: [CheckRecord]) -> [FactBucket: Int] {
        var out: [FactBucket: Int] = [:]
        for (rating, n) in factCounts(checks) { out[FactBucket.of(rating), default: 0] += n }
        return out
    }

    public static func scanBuckets(_ checks: [CheckRecord]) -> [ScanBucket: Int] {
        var out: [ScanBucket: Int] = [:]
        for c in checks where c.kind == .scan {
            if let v = Verdict(rawValue: c.outcome) { out[ScanBucket.of(v), default: 0] += 1 }
        }
        return out
    }
}

// MARK: - Storage

/// A small JSON file holding an array, rewritten atomically. Enough for ledgers measured in thousands of rows.
public struct JSONLedger<Item: Codable & Sendable>: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func defaultURL(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TruthLens", isDirectory: true).appendingPathComponent(name)
    }

    public func load() -> [Item] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([Item].self, from: data)) ?? []
    }

    public func save(_ items: [Item]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(items) { try? data.write(to: url, options: .atomic) }
    }
}
