import SwiftUI
import TruthLensCore

struct StatsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmReset: ResetKind?

    private enum ResetKind: Identifiable {
        case results, usage
        var id: Int { self == .results ? 0 : 1 }
    }

    private var tracker: UsageTracker { app.usage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overview
                    factCard
                    scanCard
                    costCard
                    pricingCard
                    resetCard
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Background())
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { app.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .confirmationDialog(confirmReset == .results ? "Reset result stats?" : "Reset usage and cost totals?",
                            isPresented: Binding(get: { confirmReset != nil }, set: { if !$0 { confirmReset = nil } }),
                            titleVisibility: .visible, presenting: confirmReset) { kind in
            Button("Reset", role: .destructive) {
                if kind == .results { tracker.resetResults() } else { tracker.resetUsage() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(kind == .results
                 ? "Clears the counts of true, false and AI results. Your History isn't affected."
                 : "Clears the cost and usage totals. This doesn't change what Anthropic bills you.")
        }
    }

    // MARK: Results

    private var overview: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(tracker.factCount + tracker.scanCount)", label: "Checks done", symbol: "checkmark.circle")
            StatTile(value: "\(tracker.factCount)", label: "Fact checks", symbol: "checkmark.seal")
            StatTile(value: "\(tracker.scanCount)", label: "AI scans", symbol: "sparkle.magnifyingglass")
        }
    }

    private var factCard: some View {
        let buckets = ResultStats.factBuckets(tracker.checks)
        let total = max(tracker.factCount, 1)
        let counts = ResultStats.factCounts(tracker.checks)
        return VStack(alignment: .leading, spacing: 14) {
            Label("Fact check results", systemImage: "checkmark.seal.fill").font(.headline)
            if tracker.factCount == 0 {
                emptyNote("Run a fact check and your true, false and mixed results add up here.")
            } else {
                ForEach(FactBucket.allCases, id: \.self) { b in
                    OutcomeRow(title: b.title, blurb: b.blurb, symbol: b.symbol, color: b.color,
                               count: buckets[b] ?? 0, total: total)
                }
                DisclosureGroup("By exact rating") {
                    VStack(spacing: 6) {
                        ForEach(ClaimRating.allCases, id: \.self) { r in
                            HStack {
                                Label(r.title, systemImage: r.symbol).foregroundStyle(.primary)
                                Spacer()
                                Text("\(counts[r] ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var scanCard: some View {
        let buckets = ResultStats.scanBuckets(tracker.checks)
        let total = max(tracker.scanCount, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Label("AI scan results", systemImage: "sparkle.magnifyingglass").font(.headline)
            if tracker.scanCount == 0 {
                emptyNote("Scan a photo, video or audio file and your results add up here.")
            } else {
                ForEach(ScanBucket.allCases, id: \.self) { b in
                    OutcomeRow(title: b.title, blurb: b.blurb, symbol: b.symbol, color: b.color,
                               count: buckets[b] ?? 0, total: total)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Cost

    private var costCard: some View {
        let all = tracker.allTime
        return VStack(alignment: .leading, spacing: 14) {
            Label("Usage and cost", systemImage: "dollarsign.circle.fill").font(.headline)
            HStack(spacing: 12) {
                StatTile(value: Money.format(tracker.today.cost), label: "Today", symbol: nil)
                StatTile(value: Money.format(tracker.thisMonth.cost), label: "This month", symbol: nil)
                StatTile(value: Money.format(all.cost), label: "All time", symbol: nil)
            }
            if all.calls == 0 {
                emptyNote("Costs appear after your first scan or fact check.")
            } else {
                VStack(spacing: 10) {
                    ForEach(UsageKind.allCases, id: \.self) { kind in
                        let s = tracker.summary(kind)
                        if s.calls > 0 {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title).font(.subheadline.weight(.semibold))
                                    Text("\(s.calls) · avg \(Money.format(s.averageCost ?? 0)) each")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(s.cost)).font(.subheadline.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Divider()
                Text("\(all.calls) API calls · \(all.inputTokens.formatted()) tokens in · \(all.outputTokens.formatted()) out · \(all.searches.formatted()) web searches")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var pricingCard: some View {
        let p = app.pricing
        let perSearch = p.searchPer1000 / 1_000
        return VStack(alignment: .leading, spacing: 10) {
            Label("How you're charged", systemImage: "key.fill").font(.headline)
            Text("TruthLens uses your own Anthropic API key, so Anthropic bills your account directly for each use. Nothing goes through a TruthLens server, and there is no subscription.")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                bullet("Tokens: \(Money.format(p.inputPerMTok)) per million in, \(Money.format(p.outputPerMTok)) per million out (\(app.client.model)).")
                bullet("Web search: \(Money.format(perSearch)) per search, plus the tokens for the pages it reads.")
                bullet("Search depth sets the most searches per fact check: Quick \(FactDepth.quick.maxSearches) (up to \(Money.format(Double(FactDepth.quick.maxSearches) * perSearch))), Standard \(FactDepth.standard.maxSearches) (\(Money.format(Double(FactDepth.standard.maxSearches) * perSearch))), Thorough \(FactDepth.thorough.maxSearches) (\(Money.format(Double(FactDepth.thorough.maxSearches) * perSearch))), before token costs.")
                bullet("Replies, Community Notes and audio playback: replies and notes use a small number of tokens. Audio is on your device and free.")
            }
            .font(.footnote).foregroundStyle(.secondary)
            Text("These are estimates from Anthropic's published rates. Your Anthropic Console shows the exact bill.")
                .font(.footnote.weight(.semibold))
            Link("Open the Anthropic Console", destination: URL(string: "https://console.anthropic.com/")!)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var resetCard: some View {
        HStack(spacing: 10) {
            Button("Reset results", role: .destructive) { confirmReset = .results }
                .disabled(tracker.checks.isEmpty)
            Button("Reset usage", role: .destructive) { confirmReset = .usage }
                .disabled(tracker.usage.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); Text(text) }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}

// MARK: - Pieces

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.subheadline).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(value).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One category: icon and label say what it is (never color alone), a thin bar shows the share, the numbers are written out.
struct OutcomeRow: View {
    let title: String
    let blurb: String
    let symbol: String
    let color: Color
    let count: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(count) / Double(total) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label { Text(title).font(.subheadline.weight(.semibold)) } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
                Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit())
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if count > 0 { Capsule().fill(color).frame(width: max(8, g.size.width * fraction)) }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(blurb): \(count) of \(total), \(Int((fraction * 100).rounded())) percent")
    }
}

extension FactBucket {
    var symbol: String {
        switch self {
        case .true_: "checkmark.circle.fill"
        case .mixed: "circle.lefthalf.filled"
        case .false_: "xmark.circle.fill"
        case .unclear: "questionmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .true_: .green
        case .mixed: .orange
        case .false_: .red
        case .unclear: .gray
        }
    }
}

extension ScanBucket {
    var symbol: String {
        switch self {
        case .ai: "sparkles"
        case .inconclusive: "questionmark.circle.fill"
        case .authentic: "checkmark.seal.fill"
        }
    }
    var color: Color {
        switch self {
        case .ai: .red
        case .inconclusive: .gray
        case .authentic: .green
        }
    }
}
