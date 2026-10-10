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

    public func analyze(_ media: PreparedMedia, context: UserContext = .init()) async throws -> AnalysisReport {
        var content: [[String: Any]] = media.frames.map {
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        content.append(["type": "text",
                        "text": Prompts.analysisUser(kind: media.kind, frameCount: media.frames.count,
                                                     signals: MetadataAnalyzer.summary(media.signals),
                                                     context: context)])
        let text = try await send(system: Prompts.analysisSystem, content: content,
                                  webSearch: true, maxTokens: 4096)
        var report = try Self.parseReport(text)
        report = Self.applyMetadataFloor(report, signals: media.signals)
        return report
    }

    public func draftReply(for report: AnalysisReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        let limit = platform.characterLimit
        let prompt = Prompts.replyUser(report: report, platform: platform, tone: tone, limit: limit)
        let text = try await send(system: Prompts.replySystem, content: [["type": "text", "text": prompt]],
                                  webSearch: false, maxTokens: 1024)
        return ReplyLength.fit(text, limit: limit)
    }

    // MARK: Parsing (internal for tests)

    static func parseReport(_ text: String) throws -> AnalysisReport {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { throw ClaudeError.badResponse }
        do {
            let r = try JSONDecoder().decode(AnalysisReport.self, from: data)
            return AnalysisReport(aiScore: min(max(r.aiScore, 0), 100), verdict: r.verdict, headline: r.headline,
                                  reasons: r.reasons, risks: r.risks, factCheck: r.factCheck)
        } catch {
            throw ClaudeError.badResponse
        }
    }

    /// A hard embedded AI marker should never be argued away by a model that only saw pixels.
    static func applyMetadataFloor(_ r: AnalysisReport, signals: [MetadataSignal]) -> AnalysisReport {
        guard let hit = signals.first(where: { $0.strength == .strongAI }), r.aiScore < 90 else { return r }
        var reasons = r.reasons
        reasons.insert(Reason(title: hit.label, detail: hit.detail, source: .metadata, indicatesAI: true), at: 0)
        return AnalysisReport(aiScore: 95, verdict: .aiGenerated,
                              headline: "The file itself is labelled as AI-generated.",
                              reasons: reasons, risks: r.risks, factCheck: r.factCheck)
    }

    // MARK: Transport

    private func send(system: String, content: [[String: Any]], webSearch: Bool, maxTokens: Int) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        if webSearch {
            body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": 5]]
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
        return text
    }
}
