import Foundation

public enum ReplyPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case facebook, threads, x, bluesky, mastodon, instagram, linkedin, reddit, messages

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .x: "X"
        case .messages: "Messages"
        case .linkedin: "LinkedIn"
        default: rawValue.capitalized
        }
    }

    /// Character limit for a single reply/comment.
    public var characterLimit: Int {
        switch self {
        case .facebook: 8_000       // practical comment length; hard cap is far higher
        case .threads: 500
        case .x: 280
        case .bluesky: 300
        case .mastodon: 500
        case .instagram: 2_200
        case .linkedin: 1_250
        case .reddit: 10_000
        case .messages: 2_000
        }
    }

    public var styleHint: String {
        switch self {
        case .facebook: "Conversational, can be a short paragraph or two. Plain text."
        case .threads: "Casual and punchy. Plain text."
        case .x: "Very tight and punchy."
        case .bluesky: "Casual, concise."
        case .mastodon: "Friendly, concise, no hashtags needed."
        case .instagram: "Friendly and brief. Emoji acceptable sparingly."
        case .linkedin: "Professional and measured."
        case .reddit: "Direct, can use short paragraphs. Markdown allowed."
        case .messages: "Personal, like texting a friend."
        }
    }
}

public enum ReplyTone: String, CaseIterable, Identifiable, Sendable {
    case calm, firm, friendly, witty, educational
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum ReplyLength {
    /// Hard-trims at a word boundary so a reply never exceeds the platform limit.
    public static func fit(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1 else { return "" }
        guard trimmed.count > limit else { return trimmed }
        let cut = String(trimmed.prefix(limit - 1))
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) + "…" }
        return cut + "…"
    }
}
