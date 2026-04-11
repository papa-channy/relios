/// `MAJOR.MINOR.PATCH` triple. Pre-release tags and metadata are not
/// supported in v1 — the spec doc gates them out as YAGNI.
public struct SemanticVersion: Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(parsing string: String) throws {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0
        else {
            throw VersionSourceError.unparseableSemver(raw: string)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Returns the next version under `kind`. `.none` returns self unchanged.
    /// Bumping `minor` resets `patch` to 0; bumping `major` resets both.
    public func bumped(_ kind: BumpKind) -> SemanticVersion {
        switch kind {
        case .none:
            return self
        case .patch:
            return SemanticVersion(major: major, minor: minor, patch: patch + 1)
        case .minor:
            return SemanticVersion(major: major, minor: minor + 1, patch: 0)
        case .major:
            return SemanticVersion(major: major + 1, minor: 0, patch: 0)
        }
    }

    public var formatted: String {
        "\(major).\(minor).\(patch)"
    }
}
