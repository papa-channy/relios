/// Monotonic non-negative integer used as the second half of "version (build)".
///
/// Independent of `SemanticVersion`: a release that bumps `patch/minor/major`
/// resets the build number to 1, while a release with `BumpKind.none`
/// only increments it.
public struct BuildNumber: Sendable, Equatable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(parsing string: String) throws {
        guard let parsed = Int(string), parsed >= 0 else {
            throw VersionSourceError.unparseableBuild(raw: string)
        }
        self.value = parsed
    }

    public func incremented() -> BuildNumber {
        BuildNumber(value + 1)
    }

    public static let initial = BuildNumber(1)

    public var formatted: String {
        "\(value)"
    }
}
