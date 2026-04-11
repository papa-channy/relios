import ReliosSupport

/// Common bundle of dependencies a `ValidationRule` may need.
///
/// v1 carries the spec, the absolutized project root, and the filesystem.
/// `process: ProcessRunner` and `versionReader: VersionSourceReader` will
/// be added in later slices when the rules that need them land — adding
/// fields is non-breaking for existing rules that ignore them.
public struct ValidationContext: Sendable {
    public let spec: ReleaseSpec
    public let projectRoot: String
    public let fs: any FileSystem
    /// Optional: only needed by BuildReadinessRule and SigningReadinessRule.
    /// `nil` in unit tests that don't exercise process-dependent rules.
    public let process: (any ProcessRunner)?

    public init(
        spec: ReleaseSpec,
        projectRoot: String,
        fs: any FileSystem,
        process: (any ProcessRunner)? = nil
    ) {
        self.spec = spec
        self.projectRoot = projectRoot
        self.fs = fs
        self.process = process
    }
}
