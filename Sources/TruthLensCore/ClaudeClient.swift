import Foundation

public enum ClaudeError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings first."
        case .http(let code, let msg): "The API returned \(code): \(msg)"
        case .badResponse: "The analysis response couldn't be understood. Try again."
        }
    }
}

public struct ClaudeClient: Sendable {
    public var apiKey: String
    public var model: String
    public var session: URLSession

    public init(apiKey: String, model: String = "claude-sonnet-5-5", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    // MARK: Public API

    public func analyze(_ media: PreparedMedia) async throws -> AnalysisReport {
        var content: [[String: Any]] = media.frames.map {
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        content.append(["type": "text",
                        "text": Prompts.analysisUser(kind: media.kind, frameCount: media.frames.count,
                                                     signals: MetadataAnalyzer.summary(media.signals))])
        let text = try await send(system: Prompts.analysisSystem, content: content,
                                  webSearchUses: 3, maxTokens: 4096).text
        var report = try Self.parseReport(text)
        report = Self.applyMetadataFloor(report, signals: media.signals)
        return report
    }

    public func draftReply(for report: AnalysisReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        let limit = platform.characterLimit
        let prompt = Prompts.replyUser(report: report, platform: platform, tone: tone, limit: limit)
        let text = try await send(system: Prompts.replySystem, content: [["type": "text", "text": prompt]],
                                  webSearchUses: 0, maxTokens: 1024).text
        return ReplyLength.fit(text, limit: limit)
    }

    /// Checks one claim against independent sources found with web search.
    /// - Parameters:
    ///   - claim: the statement to check (may be empty if a screenshot is supplied)
    ///   - speaker: who said it / where it appeared (optional)
    ///   - url: link to the original post (optional)
    ///   - screenshot: JPEG data of a screenshot of the post (optional)
    public func factCheck(claim: String, speaker: String = "", url: String = "",
                          screenshot: Data? = nil, today: Date = .now) async throws -> FactCheckReport {
        var content: [[String: Any]] = []
        if let screenshot {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": screenshot.base64EncodedString()]])
        }
        let day = today.formatted(.iso8601.year().month().day())
        content.append(["type": "text",
                        "text": Prompts.factCheckUser(claim: claim, speaker: speaker, url: url,
                                                      hasScreenshot: screenshot != nil, today: day)])
        let reply = try await send(system: Prompts.factCheckSystem, content: content,
                                   webSearchUses: 8, maxTokens: 6000)
        let report = try Self.parseFactCheck(reply.text)
        return Self.keepRetrievedSources(report, retrieved: reply.retrievedURLs)
    }

    public func draftReply(for report: FactCheckReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        let limit = platform.characterLimit
        let prompt = Prompts.factReplyUser(report: report, platform: platform, tone: tone, limit: limit)
        let text = try await send(system: Prompts.factReplySystem, content: [["type": "text", "text": prompt]],
                                  webSearchUses: 0, maxTokens: 1024).text
        return ReplyLength.fit(text, limit: limit)
    }

    /// Drafts the text of a Community Note (without its link). Combine with `CommunityNote.compose`.
    public func draftCommunityNote(for report: FactCheckReport, source: FactSource) async throws -> String {
        let budget = CommunityNote.bodyBudget(source: source)
        let prompt = Prompts.noteUser(report: report, source: source, budget: budget)
        let text = try await send(system: Prompts.noteSystem, content: [["type": "text", "text": prompt]],
                                  webSearchUses: 0, maxTokens: 600).text
        return ReplyLength.fit(text, limit: budget)
    }

    // MARK: Parsing (internal for tests)

    static func parseReport(_ text: String) throws -> AnalysisReport {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { throw ClaudeError.badResponse }
        do {
            let r = try JSONDecoder().decode(AnalysisReport.self, from: data)
            return AnalysisReport(aiScore: min(max(r.aiScore, 0), 100), verdict: r.verdict, headline: r.headline,
                                  reasons: r.reasons, risks: r.risks)
        } catch {
            throw ClaudeError.badResponse
        }
    }

    static func parseFactCheck(_ text: String) throws -> FactCheckReport {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { throw ClaudeError.badResponse }
        do { return try JSONDecoder().decode(FactCheckReport.self, from: data) }
        catch { throw ClaudeError.badResponse }
    }

    /// Drops any cited URL the search tool never actually returned, so a hallucinated link can't reach the user.
    /// If that leaves a definitive rating with no backing source, it is downgraded to "unverified".
    static func keepRetrievedSources(_ r: FactCheckReport, retrieved: Set<String>) -> FactCheckReport {
        let kept = r.sources.filter { retrieved.contains(Self.normalizedURL($0.url)) }
        let definitive: Set<ClaimRating> = [.true_, .mostlyTrue, .partiallyTrue, .misleading, .mostlyFalse, .false_]
        guard kept.isEmpty, definitive.contains(r.rating) else {
            return FactCheckReport(claim: r.claim, rating: r.rating, headline: r.headline, explanation: r.explanation,
                                   evidence: r.evidence, sources: kept, caveats: r.caveats)
        }
        let note = "No verifiable sources could be confirmed, so the rating was reset to Unverified."
        return FactCheckReport(claim: r.claim, rating: .unverified, headline: "Couldn't verify this claim.",
                               explanation: r.explanation, evidence: r.evidence, sources: [],
                               caveats: [note, r.caveats].compactMap { $0 }.joined(separator: " "))
    }

    static func normalizedURL(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hash = t.firstIndex(of: "#") { t = String(t[..<hash]) }
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }

    /// A hard embedded AI marker should never be argued away by a model that only saw pixels.
    static func applyMetadataFloor(_ r: AnalysisReport, signals: [MetadataSignal]) -> AnalysisReport {
        guard let hit = signals.first(where: { $0.strength == .strongAI }), r.aiScore < 90 else { return r }
        var reasons = r.reasons
        reasons.insert(Reason(title: hit.label, detail: hit.detail, source: .metadata, indicatesAI: true), at: 0)
        return AnalysisReport(aiScore: 95, verdict: .aiGenerated,
                              headline: "The file itself is labelled as AI-generated.",
                              reasons: reasons, risks: r.risks)
    }

    // MARK: Transport

    struct Reply {
        let text: String
        /// URLs the web_search tool actually returned, normalised.
        let retrievedURLs: Set<String>
    }

    private func send(system: String, content: [[String: Any]], webSearchUses: Int, maxTokens: Int) async throws -> Reply {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        if webSearchUses > 0 {
            body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": webSearchUses]]
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? "Unknown error"
            throw ClaudeError.http(code, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw ClaudeError.badResponse }
        // With web search the answer is spread over several text blocks; the JSON ends up in the last ones.
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        var urls = Set<String>()
        for block in blocks where block["type"] as? String == "web_search_tool_result" {
            for hit in block["content"] as? [[String: Any]] ?? [] {
                if let u = hit["url"] as? String { urls.insert(Self.normalizedURL(u)) }
            }
        }
        return Reply(text: text, retrievedURLs: urls)
    }
}
