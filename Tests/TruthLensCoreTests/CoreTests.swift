import XCTest
@testable import TruthLensCore

final class CoreTests: XCTestCase {
    func testDetectsAIMarkerInMetadata() {
        let blob = Data("<x:xmpmeta> http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia </x:xmpmeta>".utf8)
        let signals = MetadataAnalyzer.analyze(blob, kind: .image)
        XCTAssertTrue(signals.contains { $0.strength == .strongAI })
    }

    func testCleanFileIsNeutral() {
        let signals = MetadataAnalyzer.analyze(Data("hello".utf8), kind: .audio)
        XCTAssertFalse(signals.contains { $0.strength == .strongAI })
        XCTAssertEqual(signals.count, 1)
    }

    func testReplyNeverExceedsLimit() {
        let long = String(repeating: "word ", count: 200)
        for p in ReplyPlatform.allCases {
            XCTAssertLessThanOrEqual(ReplyLength.fit(long, limit: p.characterLimit).count, p.characterLimit)
        }
        XCTAssertEqual(ReplyPlatform.threads.characterLimit, 500)
    }

    func testParsesReportWrappedInProse() throws {
        let text = """
        Here you go:
        {"aiScore": 140, "verdict": "likelyAI", "headline": "h",
         "reasons": [{"title":"Hands","detail":"Six fingers","source":"visual","indicatesAI":true}],
         "risks": [{"category":"propaganda","explanation":"x"}],
         "factCheck": {"claim":"c","rating":"false","summary":"s","sources":[{"title":"t","url":"https://e.com"}]}}
        """
        let r = try ClaudeClient.parseReport(text)
        XCTAssertEqual(r.aiScore, 100)
        XCTAssertEqual(r.factCheck?.rating, .false_)
        XCTAssertEqual(r.risks.first?.category, .propaganda)
    }

    func testMetadataFloorOverridesLowScore() throws {
        let r = AnalysisReport(aiScore: 20, verdict: .likelyAuthentic, headline: "", reasons: [], risks: [], factCheck: nil)
        let sig = MetadataSignal(label: "AI marker", detail: "d", strength: .strongAI)
        XCTAssertEqual(ClaudeClient.applyMetadataFloor(r, signals: [sig]).verdict, .aiGenerated)
    }
}
