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

    // MARK: History

    private func tempStorage() -> HistoryStorage {
        HistoryStorage(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("truthlens-tests-\(UUID().uuidString)"))
    }

    private func scanEntry(protected: Bool = false, date: Date = .now, thumb: Bool = false) -> HistoryEntry {
        HistoryEntry(date: date, kind: .scan, protected: protected, hasThumbnail: thumb,
                     scan: ScanRecord(mediaKind: .image,
                                      report: AnalysisReport(aiScore: 82, verdict: .likelyAI, headline: "Looks synthetic",
                                                             reasons: [], risks: [])))
    }

    private func factEntry(protected: Bool = false, date: Date = .now) -> HistoryEntry {
        let src = source("https://eia.gov/x", .contradicts)
        let answer = FollowUpAnswer(answer: "a", sources: [src],
                                    revision: Revision(rating: .partiallyTrue, headline: "h2", reason: "r"))
        return HistoryEntry(date: date, kind: .factCheck, protected: protected, hasThumbnail: false,
                            fact: FactRecord(claim: "Gas is down", speaker: "A commentator", url: "https://x.com/p",
                                             depth: "standard", report: report(.false_, sources: [src]),
                                             thread: [StoredFollowUp(question: "q", answer: answer, applied: true)]))
    }

    func testHistoryRoundTripKeepsClaimThreadAndThumbnail() throws {
        let store = tempStorage(); defer { try? FileManager.default.removeItem(at: store.root) }
        let fact = factEntry(), scan = scanEntry(thumb: true)
        try store.save(fact)
        try store.save(scan, thumbnail: Data("jpeg-bytes".utf8))
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.count, 2)
        let f = try XCTUnwrap(loaded.first { $0.id == fact.id }?.fact)
        XCTAssertEqual(f.claim, "Gas is down")
        XCTAssertEqual(f.report.rating, .false_)
        XCTAssertEqual(f.thread.first?.answer.revision?.rating, .partiallyTrue)
        XCTAssertTrue(f.thread.first?.applied == true)
        XCTAssertEqual(store.thumbnail(for: scan.id), Data("jpeg-bytes".utf8))
        XCTAssertNil(store.thumbnail(for: fact.id))
    }

    func testResavingAnEntryKeepsItsThumbnail() throws {
        let store = tempStorage(); defer { try? FileManager.default.removeItem(at: store.root) }
        var e = scanEntry(thumb: true)
        try store.save(e, thumbnail: Data("t".utf8))
        e.protected = true
        try store.save(e)
        XCTAssertEqual(store.thumbnail(for: e.id), Data("t".utf8))
        XCTAssertTrue(store.loadAll().first?.protected == true)
    }

    func testLoadIsNewestFirstAndSkipsCorruptFolders() throws {
        let store = tempStorage(); defer { try? FileManager.default.removeItem(at: store.root) }
        let old = scanEntry(date: Date(timeIntervalSince1970: 1_000)), new = scanEntry(date: Date(timeIntervalSince1970: 2_000))
        try store.save(old); try store.save(new)
        let junk = store.root.appendingPathComponent("junk"); try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: junk.appendingPathComponent("item.json"))
        XCTAssertEqual(store.loadAll().map(\.id), [new.id, old.id])
    }

    func testDeleteAndSizeAccounting() throws {
        let store = tempStorage(); defer { try? FileManager.default.removeItem(at: store.root) }
        let a = scanEntry(thumb: true), b = scanEntry()
        try store.save(a, thumbnail: Data(repeating: 1, count: 5_000)); try store.save(b)
        XCTAssertGreaterThan(store.bytes(of: a.id), 5_000)
        XCTAssertEqual(store.totalBytes(), store.bytes(of: a.id) + store.bytes(of: b.id))
        store.delete([a.id])
        XCTAssertEqual(store.loadAll().map(\.id), [b.id])
        XCTAssertEqual(store.totalBytes(), store.bytes(of: b.id))
        XCTAssertEqual(store.bytes(of: a.id), 0)
    }

    func testProtectedEntriesSurviveClearAndBulkDelete() {
        let keep = scanEntry(protected: true), drop = factEntry()
        let all = [keep, drop]
        XCTAssertEqual(HistoryPolicy.clearable(all).map(\.id), [drop.id])
        let split = HistoryPolicy.split(selection: [keep.id, drop.id], in: all)
        XCTAssertEqual(split.deletable, [drop.id])
        XCTAssertEqual(split.keptProtected, 1)
    }

    func testEntryTitleBadgeAndSearch() {
        XCTAssertEqual(scanEntry().badge, "Likely AI · 82")
        let f = factEntry()
        XCTAssertEqual(f.title, f.fact?.report.claim)
        XCTAssertTrue(f.searchText.contains("gas is down"))
        XCTAssertEqual(f.badge, "False")
        XCTAssertTrue(f.searchText.contains("commentator"))
    }

    func testThumbnailIsMuchSmallerThanTheOriginal() throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 2000, height: 1500, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for i in 0..<40 {
            ctx.setFillColor(red: CGFloat(i % 7) / 7, green: CGFloat(i % 5) / 5, blue: CGFloat(i % 3) / 3, alpha: 1)
            ctx.fill(CGRect(x: i * 50, y: i * 37, width: 300, height: 200))
        }
        let original = try XCTUnwrap(MediaPreparer.jpeg(try XCTUnwrap(ctx.makeImage())))
        let thumb = try XCTUnwrap(MediaPreparer.thumbnail(from: original, maxPixel: 480))
        XCTAssertLessThan(thumb.count, original.count / 3)
    }

    // MARK: Spoken text

    func testSpokenTextDropsUrlsMarkdownAndEmoji() {
        XCTAssertEqual(SpokenText.clean("Gas is **down** 🚗 per https://eia.gov/gas?x=1 #prices"), "Gas is down per link prices")
    }

    func testSpokenTextKeepsLineBreaksAsPauses() {
        XCTAssertEqual(SpokenText.clean("First.   \n\n  Second.\t Third"), "First.\nSecond. Third")
        XCTAssertEqual(SpokenText.clean("   \n  "), "")
    }
}

