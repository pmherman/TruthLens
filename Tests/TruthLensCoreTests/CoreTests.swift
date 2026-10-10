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

    // MARK: Community notes

    private func report(_ rating: ClaimRating, sources: [FactSource]) -> FactCheckReport {
        FactCheckReport(claim: "c", rating: rating, headline: "h", explanation: "e", evidence: [],
                        sources: sources, caveats: nil)
    }

    private func source(_ url: String, _ stance: Stance) -> FactSource {
        FactSource(title: "t", publisher: "p", url: url, finding: "f", stance: stance)
    }

    func testNotePicksSourceThatMatchesRating() {
        let ctx = source("https://a.com", .context), sup = source("https://b.com", .supports)
        let con = source("https://c.com", .contradicts)
        XCTAssertEqual(CommunityNote.bestSource(for: report(.false_, sources: [ctx, sup, con]))?.url, "https://c.com")
        XCTAssertEqual(CommunityNote.bestSource(for: report(.true_, sources: [ctx, con, sup]))?.url, "https://b.com")
        XCTAssertEqual(CommunityNote.bestSource(for: report(.false_, sources: [ctx, sup]))?.url, "https://b.com")
        XCTAssertNil(CommunityNote.bestSource(for: report(.false_, sources: [])))
    }

    func testNoteWithLinkNeverExceedsLimit() {
        let src = source("https://www.eia.gov/dnav/pet/pet_pri_gnd_dcus_nus_w.htm", .contradicts)
        let note = CommunityNote.compose(body: String(repeating: "word ", count: 300), source: src)
        XCTAssertLessThanOrEqual(note.count, CommunityNote.characterLimit)
        XCTAssertTrue(note.hasSuffix(src.url))
    }

    func testShortNoteKeepsBodyAndLink() {
        let src = source("https://e.com", .supports)
        XCTAssertEqual(CommunityNote.compose(body: "Context.", source: src), "Context. https://e.com")
    }

    func testNotesAreForContextNotForTrueClaims() {
        XCTAssertTrue(CommunityNote.isUsuallyWarranted(.misleading))
        XCTAssertFalse(CommunityNote.isUsuallyWarranted(.true_))
    }

    func testFitWithNoRoomReturnsEmptyInsteadOfCrashing() {
        XCTAssertEqual(ReplyLength.fit("hello world", limit: 0), "")
        let huge = source("https://e.com/" + String(repeating: "a", count: 600), .supports)
        XCTAssertLessThanOrEqual(CommunityNote.compose(body: "Context.", source: huge).count, huge.url.count)
    }

    // MARK: Streaming and follow-ups

    func testStreamAccumulatorTracksSearchesResultsAndText() throws {
        var acc = StreamAccumulator()
        func feed(_ json: String) throws -> SearchProgress? {
            try acc.consume(try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any])
        }
        XCTAssertNil(try feed(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Let me search. "}}"#))
        XCTAssertNil(try feed(#"{"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","name":"web_search"}}"#))
        XCTAssertNil(try feed(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"que"}}"#))
        XCTAssertNil(try feed(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ry\":\"gas prices\"}"}}"#))
        XCTAssertEqual(try feed(#"{"type":"content_block_stop","index":1}"#), .searching("gas prices"))
        XCTAssertEqual(try feed(#"{"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","content":[{"type":"web_search_result","url":"https://EIA.gov/gas/","title":"t"}]}}"#), .reading(1))
        XCTAssertEqual(try feed(#"{"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}"#), .writing)
        XCTAssertNil(try feed(#"{"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"{\"ok\":1}"}}"#))
        XCTAssertEqual(acc.text, "Let me search. {\"ok\":1}")
        XCTAssertEqual(acc.urls, ["https://eia.gov/gas"])
    }

    func testStreamErrorEventThrows() {
        var acc = StreamAccumulator()
        XCTAssertThrowsError(try acc.consume(["type": "error", "error": ["message": "Overloaded"]]))
    }

    private let followUpJSON = """
    {"answer":"a","sources":[{"title":"t","publisher":"p","url":"https://new.example/x","finding":"f","stance":"supports"}],
     "revision":{"rating":"mostly-true","headline":"h","reason":"r"}}
    """

    func testFollowUpRevisionNeedsAVerifiedSource() throws {
        let parsed = try ClaudeClient.parseFollowUp(followUpJSON)
        XCTAssertEqual(parsed.revision?.rating, .mostlyTrue)
        let unverified = ClaudeClient.keepVerifiedSources(parsed, retrieved: [], known: [])
        XCTAssertNil(unverified.revision)
        XCTAssertTrue(unverified.sources.isEmpty)
        let verified = ClaudeClient.keepVerifiedSources(parsed, retrieved: ["https://new.example/x"], known: [])
        XCTAssertEqual(verified.revision?.rating, .mostlyTrue)
        XCTAssertEqual(verified.sources.count, 1)
    }

    func testApplyingRevisionUpdatesRatingAndMergesNewSources() {
        let old = source("https://a.com", .contradicts), new = source("https://b.com", .supports)
        let r = report(.false_, sources: [old]).applying(Revision(rating: .partiallyTrue, headline: "new", reason: "why"),
                                                         newSources: [old, new])
        XCTAssertEqual(r.rating, .partiallyTrue)
        XCTAssertEqual(r.headline, "new")
        XCTAssertEqual(r.sources.map(\.url), ["https://a.com", "https://b.com"])
        XCTAssertTrue(r.caveats?.contains("Revised after follow-up") == true)
    }

    func testDepthLevelsGetFasterAsTheyGetShallower() {
        XCTAssertLessThan(FactDepth.quick.maxSearches, FactDepth.standard.maxSearches)
        XCTAssertLessThan(FactDepth.standard.maxSearches, FactDepth.thorough.maxSearches)
        XCTAssertTrue(Prompts.factCheckSystem(depth: .quick).contains("at most 3 web searches"))
    }
}

