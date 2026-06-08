/// Result of a successful `ReleasePipeline.run()`.
///
/// In dry-run, this is everything the user sees at the end. In a future
/// non-dry release, the same struct gains fields like `installedAt`,
/// `backupPath`, etc. — adding fields is non-breaking.
public struct ReleaseSummary: Sendable, Equatable, Encodable {
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

    private enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case previousVersion = "previous_version"
        case previousBuild = "previous_build"
        case nextVersion = "next_version"
        case nextBuild = "next_build"
        case buildCommand = "build_command"
        case binaryPath = "binary_path"
        case dryRun = "dry_run"
        case passthrough
        case signingMode = "signing_mode"
        case bundlePath = "bundle_path"
        case installedAt = "installed_at"
        case backupPath = "backup_path"
        case launched
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appName, forKey: .appName)
        try c.encode(previousVersion.formatted, forKey: .previousVersion)
        try c.encode(previousBuild.formatted, forKey: .previousBuild)
        try c.encode(nextVersion.formatted, forKey: .nextVersion)
        try c.encode(nextBuild.formatted, forKey: .nextBuild)
        try c.encode(buildCommand, forKey: .buildCommand)
        try c.encode(binaryPath, forKey: .binaryPath)
        try c.encode(dryRun, forKey: .dryRun)
        try c.encode(passthrough, forKey: .passthrough)
        try c.encode(signingMode, forKey: .signingMode)
        try c.encode(bundlePath, forKey: .bundlePath)
        try c.encode(installedAt, forKey: .installedAt)
        try c.encode(backupPath, forKey: .backupPath)
        try c.encode(launched, forKey: .launched)
    }
}
