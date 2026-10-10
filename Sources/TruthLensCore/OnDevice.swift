import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum OnDeviceStatus: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool { self == .available }
    public var message: String {
        switch self {
        case .available: "Available. Drafts are written on this device, free and private."
        case .unavailable(let why): why
        }
    }
}

public enum OnDeviceError: LocalizedError {
    case unavailable(String)
    case declined
    case tooLong
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): why
        case .declined: "The on-device model declined this topic. Add an API key to write it with Claude instead."
        case .tooLong: "That was too long for the on-device model. Try again with a shorter question."
        case .failed(let why): "The on-device model couldn't finish: \(why)"
        }
    }
}

/// Apple's on-device language model (Apple Intelligence). Free and private, but small: no web access,
/// a short context window, and it may decline sensitive topics.
public enum OnDevice {
    public static var status: OnDeviceStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable("This device doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled: return .unavailable("Turn on Apple Intelligence in System Settings.")
                case .modelNotReady: return .unavailable("The on-device model is still downloading. Try again soon.")
                @unknown default: return .unavailable("The on-device model isn't available.")
                }
            }
        }
        #endif
        return .unavailable("Needs macOS 26 or iOS 26 or later with Apple Intelligence.")
    }

    static func generate(system: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            guard status.isAvailable else { throw OnDeviceError.unavailable(status.message) }
            do {
                let session = LanguageModelSession(instructions: system)
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal: throw OnDeviceError.declined
                case .exceededContextWindowSize: throw OnDeviceError.tooLong
                default: throw OnDeviceError.failed(error.localizedDescription)
                }
            }
        }
        #endif
        throw OnDeviceError.unavailable(status.message)
    }
}

/// The same drafting jobs as `ClaudeClient`, run on the on-device model.
public struct OnDeviceWriter: Sendable {
    public init() {}

    public func draftReply(for report: AnalysisReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        let limit = platform.characterLimit
        let text = try await OnDevice.generate(
            system: Prompts.replySystem,
            prompt: Prompts.replyUser(report: report, platform: platform, tone: tone, limit: limit))
        return ReplyLength.fit(text, limit: limit)
    }

    public func draftReply(for report: FactCheckReport, platform: ReplyPlatform, tone: ReplyTone) async throws -> String {
        let limit = platform.characterLimit
        let text = try await OnDevice.generate(
            system: Prompts.factReplySystem,
            prompt: Prompts.factReplyUser(report: report, platform: platform, tone: tone, limit: limit))
        return ReplyLength.fit(text, limit: limit)
    }

    public func draftCommunityNote(for report: FactCheckReport, source: FactSource) async throws -> String {
        let budget = CommunityNote.bodyBudget(source: source)
        let text = try await OnDevice.generate(
            system: Prompts.noteSystem,
            prompt: Prompts.noteUser(report: report, source: source, budget: budget))
        return ReplyLength.fit(Self.withoutSourceTags(text), limit: budget)
    }

    /// The small model sometimes adds "[Source: ...]" even when told not to; the real link is appended separately.
    static func withoutSourceTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[\[\(]\s*sources?\s*:[^\]\)]*[\]\)]"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Answers from the existing fact check only. It can't search, so it never proposes a revision.
    public func followUp(question: String, report: FactCheckReport, history: [FollowUpTurn] = []) async throws -> FollowUpAnswer {
        let text = try await OnDevice.generate(
            system: Prompts.followUpOfflineSystem,
            prompt: Prompts.followUpOfflineUser(report: report, history: history, question: question))
        return FollowUpAnswer(answer: text, sources: [], revision: nil)
    }
}
