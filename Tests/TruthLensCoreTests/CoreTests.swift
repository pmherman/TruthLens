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
}
