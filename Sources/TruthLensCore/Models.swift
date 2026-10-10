import Foundation

public enum MediaKind: String, Codable, Sendable {
    case image, video, audio
}

public enum Verdict: String, Codable, Sendable {
    case aiGenerated, likelyAI, uncertain, likelyAuthentic, authentic

    public var title: String {
        switch self {
        case .aiGenerated: "AI-generated"
        case .likelyAI: "Likely AI"
        case .uncertain: "Inconclusive"
        case .likelyAuthentic: "Likely authentic"
        case .authentic: "Authentic"
        }
    }
}

public enum RiskCategory: String, Codable, CaseIterable, Sendable {
    case scam, catfishing, political, propaganda, deepfake, misinformation, commercial

    public var title: String { rawValue.capitalized }
}

public struct Reason: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case visual, metadata, context, audio }
    public var id: String { title + detail }
    public let title: String
    public let detail: String
    public let source: Source
    /// true = points toward AI, false = points toward authentic
    public let indicatesAI: Bool
}

public struct RiskFlag: Codable, Hashable, Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: RiskCategory
    public let explanation: String
}

public struct SourceLink: Codable, Hashable, Identifiable, Sendable {
    public var id: String { url }
    public let title: String
    public let url: String
}

public struct AnalysisReport: Codable, Sendable {
    /// 0 (certainly real) ... 100 (certainly AI)
    public let aiScore: Int
    public let verdict: Verdict
    public let headline: String
    public let reasons: [Reason]
    public let risks: [RiskFlag]
}

// MARK: - Fact checking

/// Normalises model output like "partially-true" / "Partially True" / "mostly_false" to a case.
private func normalizedKey(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter }
}

public enum ClaimRating: String, Codable, CaseIterable, Sendable {
    case true_ = "true"
    case mostlyTrue, partiallyTrue, misleading, mostlyFalse
    case false_ = "false"
    case unverified, notCheckable

    public var title: String {
        switch self {
        case .true_: "True"
        case .mostlyTrue: "Mostly true"
        case .partiallyTrue: "Partially true"
        case .misleading: "Misleading"
        case .mostlyFalse: "Mostly false"
        case .false_: "False"
        case .unverified: "Unverified"
        case .notCheckable: "Not a factual claim"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let key = normalizedKey(raw)
        self = Self.allCases.first { normalizedKey($0.rawValue) == key } ?? .unverified
    }
}

public enum Stance: String, Codable, Sendable {
    case supports, contradicts, context

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Stance(rawValue: raw.lowercased()) ?? .context
    }
}

public struct EvidencePoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String { title + detail }
    public let title: String
    public let detail: String
    public let stance: Stance
}

public struct FactSource: Codable, Hashable, Identifiable, Sendable {
    public var id: String { url }
    public let title: String
    public let publisher: String
    public let url: String
    /// What this source says about the claim, in the model's words.
    public let finding: String
    public let stance: Stance
}

public struct FactCheckReport: Codable, Sendable {
    /// The claim as checked, restated precisely.
    public let claim: String
    public let rating: ClaimRating
    public let headline: String
    public let explanation: String
    public let evidence: [EvidencePoint]
    public let sources: [FactSource]
    /// Other claims in the post, data-freshness limits, or what would change the rating.
    public let caveats: String?
}
