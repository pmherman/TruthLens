import Foundation

enum AppInfo {
    static let developer = "Paul Herman"
    static let repoURL = URL(string: "https://github.com/pmherman/TruthLens")!

    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }

    /// True when the build is exactly a tagged release (no commits after the tag, no local edits).
    static var isTaggedRelease: Bool {
        guard let describe = info["TruthLensGitDescribe"] as? String else { return true }
        return describe == "v\(version)"
    }

    /// "Version 0.0.1 (14) Alpha", plus "· unreleased changes" when the build is past its tag.
    static var versionString: String {
        var s = "Version \(version) (\(build))"
        if version.hasPrefix("0.") { s += " Alpha" }
        if !isTaggedRelease { s += " · unreleased changes" }
        return s
    }
}
