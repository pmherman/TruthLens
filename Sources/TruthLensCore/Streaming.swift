import Foundation

/// Folds Anthropic server-sent events into the final text, the URLs web search returned, and live progress.
struct StreamAccumulator {
    private(set) var text = ""
    private(set) var urls = Set<String>()
    private var usage = APIUsage()
    private var reportedSearches: Int?
    private var startedSearches = 0
    private var kinds: [Int: String] = [:]
    private var toolInput: [Int: String] = [:]

    /// Token and search usage so far. `message_delta` totals are cumulative, so the last one wins; if the stream
    /// ends early (cancelled) the searches that were started are counted instead.
    var finalUsage: APIUsage {
        var u = usage
        u.webSearches = reportedSearches ?? startedSearches
        return u
    }

    /// Feeds one decoded `data:` event. Returns progress worth showing, if any. Throws on an in-stream error.
    mutating func consume(_ event: [String: Any]) throws -> SearchProgress? {
        let index = event["index"] as? Int ?? -1
        switch event["type"] as? String {
        case "error":
            let msg = (event["error"] as? [String: Any])?["message"] as? String ?? "The stream failed."
            throw ClaudeError.http(0, msg)
        case "message_start":
            usage.merge((event["message"] as? [String: Any])?["usage"] as? [String: Any])
        case "message_delta":
            let u = event["usage"] as? [String: Any]
            usage.merge(u)
            if let n = (u?["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int { reportedSearches = n }
        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            let kind = block["type"] as? String ?? ""
            kinds[index] = kind
            if kind == "server_tool_use" && block["name"] as? String == "web_search" { startedSearches += 1 }
            if kind == "web_search_tool_result" {
                for hit in block["content"] as? [[String: Any]] ?? [] {
                    if let u = hit["url"] as? String { urls.insert(ClaudeClient.normalizedURL(u)) }
                }
                return .reading(urls.count)
            }
            if kind == "text" {
                text += block["text"] as? String ?? ""
                return urls.isEmpty ? nil : .writing
            }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta": text += delta["text"] as? String ?? ""
            case "input_json_delta": toolInput[index, default: ""] += delta["partial_json"] as? String ?? ""
            default: break
            }
        case "content_block_stop":
            if kinds[index] == "server_tool_use", let raw = toolInput[index],
               let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
               let query = obj["query"] as? String {
                return .searching(query)
            }
        default: break
        }
        return nil
    }
}
