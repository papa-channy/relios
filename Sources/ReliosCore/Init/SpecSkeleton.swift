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
    public let projectType: ProjectSection.Kind
    public let buildCommand: String
    public let binaryPath: String
    public let outputAppPath: String
    public let installPath: String
    public let bundleMode: BundleSection.Mode
    public let signingMode: SigningSection.Mode

    public init(
        appName: String,
        bundleId: String,
        binaryTarget: String,
        projectRoot: String,
        projectType: ProjectSection.Kind,
        buildCommand: String,
        binaryPath: String,
        outputAppPath: String,
        installPath: String,
        bundleMode: BundleSection.Mode,
        signingMode: SigningSection.Mode
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.binaryTarget = binaryTarget
        self.projectRoot = projectRoot
        self.projectType = projectType
        self.buildCommand = buildCommand
        self.binaryPath = binaryPath
        self.outputAppPath = outputAppPath
        self.installPath = installPath
        self.bundleMode = bundleMode
        self.signingMode = signingMode
    }
}

extension SpecSkeleton {
    /// Default-fills every spec field from a scan result. The user is expected
    /// to edit `bundle_id` after init — `com.example.<name>` is a placeholder.
    public static func from(scan: ProjectScanResult) -> SpecSkeleton {
        let name = scan.binaryTarget

        switch scan.projectType {
        case .swiftpm:
            return SpecSkeleton(
                appName: name,
                bundleId: "com.example." + name.lowercased(),
                binaryTarget: name,
                projectRoot: scan.root,
                projectType: .swiftpm,
                buildCommand: "swift build -c release",
                binaryPath: ".build/release/" + name,
                outputAppPath: "dist/" + name + ".app",
                installPath: "/Applications/" + name + ".app",
                bundleMode: .assembly,
                signingMode: .adhoc
            )

        case .xcodebuild:
            // -derivedDataPath build pins the output to a predictable
            // location instead of ~/Library/Developer/Xcode/DerivedData/.
            // signing = keep: Xcode already signs the .app — don't overwrite.
            return SpecSkeleton(
                appName: name,
                bundleId: "com.example." + name.lowercased(),
                binaryTarget: name,
                projectRoot: scan.root,
                projectType: .xcodebuild,
                buildCommand: "xcodebuild -scheme \(name) -configuration Release -derivedDataPath build build",
                binaryPath: "",
                outputAppPath: "build/Build/Products/Release/\(name).app",
                installPath: "/Applications/" + name + ".app",
                bundleMode: .passthrough,
                signingMode: .keep
            )
        }
    }
}
