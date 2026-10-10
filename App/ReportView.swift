import SwiftUI
import TruthLensCore

extension AnalysisReport {
    var tint: Color {
        if isMetadataOnly { return verdict == .aiGenerated ? .red : .gray }
        return switch aiScore {
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
            if report.isMetadataOnly { FileCheckBadge(tint: report.tint) } else { ScoreRing(score: report.aiScore, tint: report.tint) }
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

/// Stands in for the score ring when only the file's metadata was checked: there is no score to show.
struct FileCheckBadge: View {
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            VStack(spacing: 2) {
                Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(tint)
                Text("File check").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metadata check only, no score")
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

extension View {
    func card() -> some View {
        padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
