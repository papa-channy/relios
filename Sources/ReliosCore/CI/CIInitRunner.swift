import ReliosSupport

/// Entry point for `relios ci init`. Loads the spec and writes two
/// workflows:
///   - `.github/workflows/release.yml` — tag-triggered release pipeline
///   - `.github/workflows/ci.yml`      — PR/push build+test gate
///
/// Refuses to clobber either file unless `force` is set. If both already
/// exist, the error lists them together so the user sees the full picture
/// in one shot (instead of re-running and hitting a second failure).
public struct CIInitRunner: Sendable {
    public struct FileResult: Equatable, Sendable, Encodable {
        public let path: String
        public let overwritten: Bool

        private enum CodingKeys: String, CodingKey {
            case path
            case overwritten
        }
    }

    public struct Result: Equatable, Sendable, Encodable {
        public let mode: BundleSection.Mode
        public let projectType: ProjectSection.Kind
        public let files: [FileResult]

        private enum CodingKeys: String, CodingKey {
            case mode
            case projectType = "project_type"
            case files
        }
    }

    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func run(projectRoot: String, force: Bool) throws -> Result {
        let specPath = projectRoot + "/relios.toml"
        guard fs.fileExists(at: specPath) else {
            throw CIError.specMissing(path: specPath)
        }

        let spec = try SpecLoader(fs: fs).load(from: specPath)

        let releasePath = projectRoot + "/.github/workflows/release.yml"
        let ciPath      = projectRoot + "/.github/workflows/ci.yml"
        let autoReleasePath = projectRoot + "/.github/workflows/auto-release.yml"

        // auto-release.yml is only generated when the auto-update feed is on —
        // continuous "push a version bump → release" is what makes it useful.
        let autoReleaseEnabled = spec.update?.enabled == true

        let releaseExists     = fs.fileExists(at: releasePath)
        let ciExists          = fs.fileExists(at: ciPath)
        let autoReleaseExists = autoReleaseEnabled && fs.fileExists(at: autoReleasePath)

        if !force {
            let conflicts = [releaseExists     ? releasePath     : nil,
                             ciExists          ? ciPath          : nil,
                             autoReleaseExists ? autoReleasePath : nil]
                .compactMap { $0 }
            if !conflicts.isEmpty {
                throw CIError.workflowExists(paths: conflicts)
            }
        }

        // Probe for a Tests/ directory. If absent, the SwiftPM CI skips
        // the `swift test` step (which would otherwise exit 1 with
        // "no tests found"). User adds Tests/ and re-runs with --force.
        let hasTests = fs.isDirectory(at: projectRoot + "/Tests")

        let releaseYAML = ReleaseWorkflowRenderer().render(spec)
        let ciYAML      = CIWorkflowRenderer().render(spec, hasTests: hasTests)

        try write(releaseYAML, to: releasePath)
        try write(ciYAML,      to: ciPath)

        var files = [
            FileResult(path: releasePath, overwritten: releaseExists),
            FileResult(path: ciPath,      overwritten: ciExists),
        ]

        if autoReleaseEnabled {
            let autoReleaseYAML = AutoReleaseWorkflowRenderer().render(spec)
            try write(autoReleaseYAML, to: autoReleasePath)
            files.append(FileResult(path: autoReleasePath, overwritten: autoReleaseExists))
        }

        return Result(
            mode:        spec.bundle.mode,
            projectType: spec.project.type,
            files: files
        )
    }

    private func write(_ content: String, to path: String) throws {
        do {
            try fs.writeUTF8(content, to: path)
        } catch {
            throw CIError.writeFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }
}
