import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct NotarizeCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "notarize",
        abstract: "Submit a zip or DMG to Apple notarization and staple the ticket."
    )

    @Argument(help: "Path to a .zip or .dmg. Omitted → resolved from [notarize].target.")
    public var path: String?

    @Option(name: .long, help: "Override [notarize].timeout_seconds.")
    public var timeout: Int?

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            printFail("spec load", error.shortReason, error.shortFix)
            throw ExitCode.failure
        }

        guard let notarize = spec.notarize, notarize.enabled else {
            printFail(
                "notarize",
                NotarizeError.disabled.shortReason,
                NotarizeError.disabled.shortFix
            )
            throw ExitCode.failure
        }

        // Resolve artifact.
        let resolver = NotarizeTargetResolver(fs: fs)
        let version = detectVersion(spec: spec, root: root, fs: fs)
        let artifact: String
        do {
            artifact = try resolver.resolve(
                spec: spec,
                projectRoot: root,
                versionString: version,
                explicitPath: path
            )
        } catch let error as NotarizeError {
            printFail("notarize", error.shortReason, error.shortFix)
            throw ExitCode.failure
        }

        // Credentials.
        let credentials: NotarizerCredentials
        do {
            credentials = try NotarizerCredentials.fromEnvironment(
                ProcessInfo.processInfo.environment
            )
        } catch let error as NotarizeError {
            printFail("notarize", error.shortReason, error.shortFix)
            throw ExitCode.failure
        }

        // Team ID sanity — fail early rather than waste a submission.
        if let specTeam = spec.signing.teamID, specTeam != credentials.teamID {
            let err = NotarizeError.teamIDMismatch(
                signing: specTeam,
                notarize: credentials.teamID
            )
            printFail("notarize", err.shortReason, err.shortFix)
            throw ExitCode.failure
        }

        // Submit + staple.
        let notarizer = Notarizer(fs: fs, process: RealProcessRunner())
        print("→ Submitting \(relative(artifact, root: root)) to Apple notarization")
        print("  (may take 2-15 minutes depending on Apple queue load)")
        let output: Notarizer.Output
        do {
            output = try notarizer.notarize(
                artifactPath: artifact,
                credentials: credentials,
                timeoutSeconds: timeout ?? notarize.timeoutSeconds
            )
        } catch let error as NotarizeError {
            printFail("notarize", error.shortReason, error.shortFix)
            throw ExitCode.failure
        }

        print("✓ Notarized + stapled \(relative(output.stapledArtifactPath, root: root))")
    }

    // MARK: - helpers

    private func detectVersion(
        spec: ReleaseSpec,
        root: String,
        fs: FileSystem
    ) -> String? {
        let sourcePath = root + "/" + spec.version.sourceFile
        guard fs.fileExists(at: sourcePath) else { return nil }
        let reader = VersionSourceReader(fs: fs)
        guard let parsed = try? reader.read(spec: spec.version, at: sourcePath) else {
            return nil
        }
        return "\(parsed.version.major).\(parsed.version.minor).\(parsed.version.patch)"
    }

    private func printFail(_ stage: String, _ reason: String, _ fix: String) {
        print("[\(stage)] failed")
        print("  Reason: \(reason)")
        print("  Fix: \(fix)")
    }

    private func relative(_ abs: String, root: String) -> String {
        let prefix = root + "/"
        return abs.hasPrefix(prefix) ? String(abs.dropFirst(prefix.count)) : abs
    }
}
