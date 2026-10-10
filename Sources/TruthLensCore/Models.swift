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

public struct FactCheck: Codable, Hashable, Sendable {
    public enum Rating: String, Codable, Sendable {
        case true_ = "true", mostlyTrue, misleading, false_ = "false", unverified, noClaim
    }
    public let claim: String
    public let rating: Rating
    public let summary: String
    public let sources: [SourceLink]
}

public struct AnalysisReport: Codable, Sendable {
    /// 0 (certainly real) ... 100 (certainly AI)
    public let aiScore: Int
    public let verdict: Verdict
    public let headline: String
    public let reasons: [Reason]
    public let risks: [RiskFlag]
    public let factCheck: FactCheck?
}

/// Optional context supplied by the user alongside the media.
public struct UserContext: Sendable {
    public var postText: String
    public var postURL: String
    public init(postText: String = "", postURL: String = "") {
        self.postText = postText
        self.postURL = postURL
    }
    public var isEmpty: Bool { postText.isEmpty && postURL.isEmpty }
}
