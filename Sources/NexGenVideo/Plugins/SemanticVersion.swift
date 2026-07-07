import Foundation

/// A minimal semantic version (`major.minor.patch`) for the loadable-pack gate —
/// enough to compare a pack's `NGVMinAppVersion` against the app's
/// `CFBundleShortVersionString`. Parsing is lenient about arity (`"1"`, `"1.2"`,
/// `"1.2.3"` all parse; missing components are 0) and ignores any pre-release /
/// build suffix after the numeric core (`"1.2.3-beta"` → `1.2.3`), but a string
/// with no leading numeric component is rejected (`nil`).
public struct SemanticVersion: Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        // Take the numeric core up to the first non [0-9.] character.
        let core = trimmed.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = parts.first, let major = Int(first) else { return nil }
        func component(_ i: Int) -> Int? {
            guard i < parts.count else { return 0 }
            return Int(parts[i])
        }
        guard let minor = component(1), let patch = component(2) else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}
