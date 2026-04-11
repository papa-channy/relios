/// User-supplied flags for one `relios release` invocation.
/// Mirrors `ReleaseCommand`'s argument surface, decoupled from ArgumentParser.
public struct ReleaseOptions: Sendable, Equatable {
    public let bump: BumpKind
    public let dryRun: Bool
    public let noOpen: Bool
    public let installPath: String?
    public let skipBackup: Bool
    public let verbose: Bool

    public init(
        bump: BumpKind = .none,
        dryRun: Bool = false,
        noOpen: Bool = false,
        installPath: String? = nil,
        skipBackup: Bool = false,
        verbose: Bool = false
    ) {
        self.bump = bump
        self.dryRun = dryRun
        self.noOpen = noOpen
        self.installPath = installPath
        self.skipBackup = skipBackup
        self.verbose = verbose
    }
}
