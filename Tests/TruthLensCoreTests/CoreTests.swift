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
         "risks": [{"category":"propaganda","explanation":"x"}]}
        """
        let r = try ClaudeClient.parseReport(text)
        XCTAssertEqual(r.aiScore, 100)
        XCTAssertEqual(r.risks.first?.category, .propaganda)
    }

    func testMetadataFloorOverridesLowScore() throws {
        let r = AnalysisReport(aiScore: 20, verdict: .likelyAuthentic, headline: "", reasons: [], risks: [])
        let sig = MetadataSignal(label: "AI marker", detail: "d", strength: .strongAI)
        XCTAssertEqual(ClaudeClient.applyMetadataFloor(r, signals: [sig]).verdict, .aiGenerated)
    }

    // MARK: Fact check

    private func factJSON(rating: String = "partially-true", url: String = "https://eia.gov/gas") -> String {
        """
        Searching… {"claim":"Gas prices are down","rating":"\(rating)","headline":"h","explanation":"e",
         "evidence":[{"title":"t","detail":"d","stance":"SUPPORTS"},{"title":"u","detail":"d","stance":"weird"}],
         "sources":[{"title":"EIA","publisher":"EIA","url":"\(url)","finding":"f","stance":"supports"}],
         "caveats":null}
        """
    }

    func testParsesFactCheckAndToleratesLooseEnums() throws {
        let r = try ClaudeClient.parseFactCheck(factJSON())
        XCTAssertEqual(r.rating, .partiallyTrue)
        XCTAssertEqual(r.evidence.map(\.stance), [.supports, .context])
        XCTAssertNil(r.caveats)
    }

    func testUnknownRatingBecomesUnverified() throws {
        XCTAssertEqual(try ClaudeClient.parseFactCheck(factJSON(rating: "who knows")).rating, .unverified)
        XCTAssertEqual(try ClaudeClient.parseFactCheck(factJSON(rating: "Mostly_False")).rating, .mostlyFalse)
    }

    func testDropsSourcesTheSearchNeverReturned() throws {
        let r = try ClaudeClient.parseFactCheck(factJSON(rating: "false", url: "https://made-up.example/x"))
        let out = ClaudeClient.keepRetrievedSources(r, retrieved: ["https://eia.gov/gas"])
        XCTAssertTrue(out.sources.isEmpty)
        XCTAssertEqual(out.rating, .unverified)
        XCTAssertNotNil(out.caveats)
    }

    func testKeepsRetrievedSourcesDespiteTrailingSlashAndCase() throws {
        let r = try ClaudeClient.parseFactCheck(factJSON(rating: "false", url: "https://EIA.gov/gas/"))
        let out = ClaudeClient.keepRetrievedSources(r, retrieved: [ClaudeClient.normalizedURL("https://eia.gov/gas")])
        XCTAssertEqual(out.sources.count, 1)
        XCTAssertEqual(out.rating, .false_)
    }
}
