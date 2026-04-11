/// Intermediate model between `ProjectScanResult` and the rendered TOML.
///
/// Why this exists instead of going directly from scan → TOML string:
/// - placeholder defaults live in one place (`from(scan:)`)
/// - `SpecSkeletonWriter` becomes pure rendering (easy to test)
/// - future flags like `--bundle-id <id>` slot in here without touching either side
public struct SpecSkeleton: Sendable, Equatable {
    public let appName: String
    public let bundleId: String
    public let binaryTarget: String
    public let projectRoot: String
    public let buildCommand: String
    public let outputAppPath: String
    public let installPath: String

    public init(
        appName: String,
        bundleId: String,
        binaryTarget: String,
        projectRoot: String,
        buildCommand: String,
        outputAppPath: String,
        installPath: String
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.binaryTarget = binaryTarget
        self.projectRoot = projectRoot
        self.buildCommand = buildCommand
        self.outputAppPath = outputAppPath
        self.installPath = installPath
    }
}

extension SpecSkeleton {
    /// Default-fills every spec field from a scan result. The user is expected
    /// to edit `bundle_id` after init — `com.example.<name>` is a placeholder.
    public static func from(scan: ProjectScanResult) -> SpecSkeleton {
        let name = scan.binaryTarget
        return SpecSkeleton(
            appName: name,
            bundleId: "com.example." + name.lowercased(),
            binaryTarget: name,
            projectRoot: scan.root,
            buildCommand: "swift build -c release",
            outputAppPath: "dist/" + name + ".app",
            installPath: "/Applications/" + name + ".app"
        )
    }
}
