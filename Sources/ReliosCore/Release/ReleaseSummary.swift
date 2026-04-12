/// Result of a successful `ReleasePipeline.run()`.
///
/// In dry-run, this is everything the user sees at the end. In a future
/// non-dry release, the same struct gains fields like `installedAt`,
/// `backupPath`, etc. — adding fields is non-breaking.
public struct ReleaseSummary: Sendable, Equatable {
    public let appName: String
    public let previousVersion: SemanticVersion
    public let previousBuild: BuildNumber
    public let nextVersion: SemanticVersion
    public let nextBuild: BuildNumber
    public let buildCommand: String
    public let binaryPath: String
    public let dryRun: Bool
    /// `true` when `[bundle].mode = "passthrough"` — assembly and plist were skipped.
    public let passthrough: Bool
    /// `"adhoc"`, `"keep"`, etc. — what signing mode was used.
    public let signingMode: String
    /// Path to the assembled .app bundle. `nil` in dry-run.
    public let bundlePath: String?
    public let installedAt: String?
    public let backupPath: String?
    public let launched: Bool

    public init(
        appName: String,
        previousVersion: SemanticVersion,
        previousBuild: BuildNumber,
        nextVersion: SemanticVersion,
        nextBuild: BuildNumber,
        buildCommand: String,
        binaryPath: String,
        dryRun: Bool,
        passthrough: Bool = false,
        signingMode: String = "adhoc",
        bundlePath: String? = nil,
        installedAt: String? = nil,
        backupPath: String? = nil,
        launched: Bool = false
    ) {
        self.appName = appName
        self.previousVersion = previousVersion
        self.previousBuild = previousBuild
        self.nextVersion = nextVersion
        self.nextBuild = nextBuild
        self.buildCommand = buildCommand
        self.binaryPath = binaryPath
        self.dryRun = dryRun
        self.passthrough = passthrough
        self.signingMode = signingMode
        self.bundlePath = bundlePath
        self.installedAt = installedAt
        self.backupPath = backupPath
        self.launched = launched
    }
}
