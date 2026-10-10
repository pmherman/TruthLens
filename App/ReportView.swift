import SwiftUI
import TruthLensCore

extension AnalysisReport {
    var tint: Color {
        switch aiScore {
        case ..<30: .green
        case 30..<60: .yellow
        case 60..<80: .orange
        default: .red
        }
    }
}

struct ReportView: View {
    let report: AnalysisReport
    let onReply: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header
            if !report.risks.isEmpty { risks }
            if let fc = report.factCheck, fc.rating != .noClaim { FactCheckCard(fact: fc) }
            reasons
            Button(action: onReply) {
                Label("Draft a reply", systemImage: "arrowshape.turn.up.left.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 18) {
            ScoreRing(score: report.aiScore, tint: report.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.verdict.title).font(.title2.bold())
                Text(report.headline).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var risks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Risk flags", systemImage: "flag.fill").font(.headline).foregroundStyle(.red)
            ForEach(report.risks) { risk in
                VStack(alignment: .leading, spacing: 2) {
                    Text(risk.category.title).font(.subheadline.bold())
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(.red.opacity(0.15), in: Capsule())
                    Text(risk.explanation).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why").font(.headline)
            ForEach(report.reasons) { reason in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: reason.indicatesAI ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(reason.indicatesAI ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(reason.title).font(.subheadline.bold())
                            Text(reason.source.rawValue).font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(reason.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ScoreRing: View {
    let score: Int
    let tint: Color
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            Circle().trim(from: 0, to: shown / 100)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)").font(.title.bold().monospacedDigit())
                Text("AI score").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = Double(score) } }
    }
}

struct FactCheckCard: View {
    let fact: FactCheck

    private var color: Color {
        switch fact.rating {
        case .true_, .mostlyTrue: .green
        case .misleading: .orange
        case .false_: .red
        default: .gray
        }
    }
    private var label: String {
        switch fact.rating {
        case .true_: "True"
        case .mostlyTrue: "Mostly true"
        case .misleading: "Misleading"
        case .false_: "False"
        case .unverified: "Unverified"
        case .noClaim: "No claim"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fact check", systemImage: "checkmark.seal.fill").font(.headline)
                Spacer()
                Text(label).font(.subheadline.bold()).foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(color.opacity(0.15), in: Capsule())
            }
            Text("“\(fact.claim)”").font(.subheadline.italic())
            Text(fact.summary).font(.subheadline).foregroundStyle(.secondary)
            ForEach(fact.sources) { src in
                if let url = URL(string: src.url) {
                    Link(destination: url) {
                        Label(src.title, systemImage: "link").font(.footnote).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension View {
    func card() -> some View {
        padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
