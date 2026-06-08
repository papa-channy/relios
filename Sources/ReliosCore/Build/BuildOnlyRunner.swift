import Foundation
import ReliosSupport

/// Runs the project's build and verifies the produced artifact — nothing else.
///
/// This is the `relios build` command's engine: it executes `[build].command`
/// and confirms the artifact exists, but does NOT bump the version, assemble a
/// bundle, sign, install, or write a manifest. It is the standalone counterpart
/// to the build+verify steps inside `ReleasePipeline`, lifted out so an agent
/// (or a developer) can compile-check without mutating any Relios-owned state.
///
/// Makes ZERO filesystem writes of its own — the only side effect is whatever
/// the build command itself writes to its caches.
public struct BuildOnlyRunner: Sendable {
    private let process: any ProcessRunner
    private let fs: any FileSystem

    public init(process: any ProcessRunner, fs: any FileSystem) {
        self.process = process
        self.fs = fs
    }

    public struct Result: Sendable, Equatable, Encodable {
        public let artifactPath: String
        public let passthrough: Bool
        public let buildCommand: String

        public init(artifactPath: String, passthrough: Bool, buildCommand: String) {
            self.artifactPath = artifactPath
            self.passthrough = passthrough
            self.buildCommand = buildCommand
        }

        private enum CodingKeys: String, CodingKey {
            case artifactPath = "artifact_path"
            case passthrough
            case buildCommand = "build_command"
        }
    }

    /// Runs the build and returns the located artifact. Throws `BuildError`
    /// (nonZeroExit/processFailed on build failure, binaryNotFound when the
    /// artifact is missing) — the same domain error the pipeline uses, so the
    /// CLI can render it with the standard reason/fix block.
    public func run(spec: ReleaseSpec, projectRoot: String) throws -> Result {
        let runner = SwiftBuildRunner(process: process, fs: fs)

        try runner.runBuild(spec: spec, projectRoot: projectRoot)

        let isPassthrough = spec.bundle.mode == .passthrough
        if isPassthrough {
            // The build command (xcodebuild) produced a complete .app; verify it.
            let outputPath = projectRoot + "/" + spec.bundle.outputPath
            guard fs.isDirectory(at: outputPath) else {
                throw BuildError.binaryNotFound(searched: [outputPath])
            }
            return Result(
                artifactPath: outputPath,
                passthrough: true,
                buildCommand: spec.build.displayCommand
            )
        }

        // Assembly mode: locate the produced binary (handles triple subdirs).
        let binary = try runner.locateBinary(spec: spec, projectRoot: projectRoot)
        return Result(
            artifactPath: binary,
            passthrough: false,
            buildCommand: spec.build.command
        )
    }
}
