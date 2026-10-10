import Foundation

/// Rules and assembly for a Meta Community Note: short, neutral, and anchored to one source link.
public enum CommunityNote {
    /// Meta's per-note limit (verify against Meta's current help pages if it changes).
    public static let characterLimit = 500

    /// The source a note should cite by default: one that backs up the rating, never a context-only link first.
    public static func bestSource(for report: FactCheckReport) -> FactSource? {
        let preferred: Stance = switch report.rating {
        case .true_, .mostlyTrue: .supports
        default: .contradicts
        }
        return report.sources.first { $0.stance == preferred }
            ?? report.sources.first { $0.stance != .context }
            ?? report.sources.first
    }

    /// Characters left for the note text once the source link and its separator are reserved.
    public static func bodyBudget(source: FactSource) -> Int {
        max(0, characterLimit - source.url.count - 1)
    }

    /// The text to paste into Meta: the note followed by its source link. Never exceeds the limit.
    public static func compose(body: String, source: FactSource) -> String {
        let fitted = ReplyLength.fit(body, limit: bodyBudget(source: source))
        return fitted.isEmpty ? source.url : fitted + " " + source.url
    }

    /// Whether a note is likely to be useful: Community Notes add missing context, so a claim rated
    /// true, or one with nothing checkable, usually doesn't need one.
    public static func isUsuallyWarranted(_ rating: ClaimRating) -> Bool {
        switch rating {
        case .partiallyTrue, .misleading, .mostlyFalse, .false_: true
        case .true_, .mostlyTrue, .unverified, .notCheckable: false
        }
    }
}
