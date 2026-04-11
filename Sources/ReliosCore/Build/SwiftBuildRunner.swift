import Foundation
import ReliosSupport

/// Runs `[build].command` via the injected `ProcessRunner` and locates the
/// produced binary on the injected `FileSystem`.
///
/// `locateBinary` exists because the spec stores a "natural" path like
/// `.build/release/PortfolioManager` but SwiftPM occasionally writes to a
/// triple-specific subdir (`.build/arm64-apple-macosx/release/...`).
/// We try the spec'd path first, then a small set of fallbacks. The fallbacks
/// are NOT exhaustive — if neither works, the user gets a clear error
/// listing every path we looked at.
public struct SwiftBuildRunner: Sendable {
    private let process: any ProcessRunner
    private let fs: any FileSystem

    public init(process: any ProcessRunner, fs: any FileSystem) {
        self.process = process
        self.fs = fs
    }

    public func runBuild(spec: ReleaseSpec, projectRoot: String) throws {
        let result: ProcessResult
        do {
            result = try process.runShell(spec.build.command, cwd: projectRoot)
        } catch {
            throw BuildError.processFailed(
                command: spec.build.command,
                underlying: String(describing: error)
            )
        }

        guard result.exitCode == 0 else {
            throw BuildError.nonZeroExit(
                command: spec.build.command,
                exitCode: result.exitCode,
                stderrTail: String(result.stderr.suffix(800))
            )
        }
    }

    public func locateBinary(spec: ReleaseSpec, projectRoot: String) throws -> String {
        let primary = projectRoot + "/" + spec.build.binaryPath
        if fs.fileExists(at: primary) {
            return primary
        }

        // Triple-specific fallbacks: spec stores the "logical" path but SwiftPM
        // sometimes writes to a triple subdir depending on toolchain config.
        let binaryName = (spec.build.binaryPath as NSString).lastPathComponent
        let fallbackPrefixes = [
            ".build/arm64-apple-macosx/release",
            ".build/x86_64-apple-macosx/release",
        ]
        var searched = [primary]
        for prefix in fallbackPrefixes {
            let candidate = projectRoot + "/" + prefix + "/" + binaryName
            searched.append(candidate)
            if fs.fileExists(at: candidate) {
                return candidate
            }
        }

        throw BuildError.binaryNotFound(searched: searched)
    }
}
