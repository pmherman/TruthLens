import Foundation

/// A scan result built only from the on-device file checks, for use without an API key.
/// It never invents a score: a hard AI marker is reported as such, and everything else is "inconclusive".
public enum MetadataReport {
    public static func make(signals: [MetadataSignal], kind: MediaKind) -> AnalysisReport {
        let reasons = signals.map {
            Reason(title: $0.label, detail: $0.detail, source: .metadata,
                   indicatesAI: $0.strength == .strongAI || $0.strength == .weakAI)
        }
        if signals.contains(where: { $0.strength == .strongAI }) {
            return AnalysisReport(aiScore: 95, verdict: .aiGenerated,
                                  headline: "The file itself is labelled as AI-generated.",
                                  reasons: reasons, risks: [], basis: .metadataOnly)
        }
        let hasCamera = signals.contains { $0.strength == .weakAuthentic || $0.strength == .strongAuthentic }
        let headline: String
        switch (kind, hasCamera) {
        case (.image, true), (.video, true):
            headline = "No AI markers found, and the file has camera data. That's a good sign, but it doesn't prove it's real."
        case (.audio, _):
            headline = "No AI markers found in the file. Audio can't be judged from metadata alone."
        default:
            headline = "No AI markers found in the file. Without a visual analysis this can't say whether it's real."
        }
        return AnalysisReport(aiScore: 50, verdict: .uncertain, headline: headline,
                              reasons: reasons, risks: [], basis: .metadataOnly)
    }
}
