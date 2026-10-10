import SwiftUI
import TruthLensCore

/// Records what each API call used and cost, plus the outcome of every check, so Stats can show both.
/// Kept separate from History on purpose: clearing history doesn't erase your totals.
@MainActor @Observable
final class UsageTracker {
    private let usageLedger = JSONLedger<UsageRecord>(url: JSONLedger<UsageRecord>.defaultURL("usage.json"))
    private let checkLedger = JSONLedger<CheckRecord>(url: JSONLedger<CheckRecord>.defaultURL("stats.json"))

    private(set) var usage: [UsageRecord] = []
    private(set) var checks: [CheckRecord] = []
    /// Cost of the most recent call of each kind, for the "this check cost" note.
    private(set) var lastCost: [UsageKind: Double] = [:]

    init() {
        usage = usageLedger.load()
        checks = checkLedger.load()
    }

    // MARK: Recording

    func record(kind: UsageKind, usage u: APIUsage, model: String) {
        let record = UsageRecord(kind: kind, model: model, usage: u)
        usage.append(record)
        lastCost[kind] = record.cost
        usageLedger.save(usage)
    }

    func recordCheck(id: UUID, kind: CheckRecord.Kind, outcome: String) {
        checks.removeAll { $0.id == id }
        checks.append(CheckRecord(id: id, kind: kind, outcome: outcome))
        checkLedger.save(checks)
    }

    /// A follow-up changed the rating, so the stats follow it.
    func updateOutcome(id: UUID?, outcome: String) {
        guard let id, let i = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[i].outcome = outcome
        checkLedger.save(checks)
    }

    func resetUsage() { usage = []; lastCost = [:]; usageLedger.save([]) }
    func resetResults() { checks = []; checkLedger.save([]) }

    // MARK: Summaries

    var today: UsageSummary { UsageStats.summary(usage, since: UsageStats.startOfToday()) }
    var thisMonth: UsageSummary { UsageStats.summary(usage, since: UsageStats.startOfMonth()) }
    var allTime: UsageSummary { UsageStats.summary(usage) }
    func summary(_ kind: UsageKind) -> UsageSummary { UsageStats.summary(usage, kind: kind) }

    var factCount: Int { checks.filter { $0.kind == .factCheck }.count }
    var scanCount: Int { checks.filter { $0.kind == .scan }.count }
}

/// "This check cost about $0.042", shown under a fresh result.
struct CostNote: View {
    let cost: Double?
    var body: some View {
        if let cost {
            Label("This check cost about \(Money.format(cost)). See the Stats tab for your totals.",
                  systemImage: "dollarsign.circle")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
