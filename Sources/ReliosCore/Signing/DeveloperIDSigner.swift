import ReliosSupport

/// Signs a .app bundle with an Apple Developer ID identity loaded from the
/// macOS keychain. Parallel to `AdhocSigner`; selection between the two
/// happens in `ReleasePipeline` based on `signing.mode`.
///
/// Command assembled:
///   codesign --force --deep --timestamp \
///     [--options runtime] [--entitlements <path>] \
///     --sign '<identity>' '<appPath>'
///
/// Hardened runtime is on by default because it is effectively required for
/// notarization; callers can opt out via `hardenedRuntime: false`.
/// Notarization is intentionally out of scope for this phase — once the app
/// is signed, the user submits it manually (or via a later `relios signing
/// notarize` subcommand).
public struct DeveloperIDSigner: Sendable {
    private let process: any ProcessRunner

    public init(process: any ProcessRunner) {
        self.process = process
    }

    public func sign(
        appPath: String,
        identity: String,
        hardenedRuntime: Bool,
        entitlementsPath: String?
    ) throws {
        var parts: [String] = ["codesign", "--force", "--deep", "--timestamp"]
        if hardenedRuntime {
            parts.append("--options")
            parts.append("runtime")
        }
        if let entitlementsPath, !entitlementsPath.isEmpty {
            parts.append("--entitlements")
            parts.append("'\(entitlementsPath)'")
        }
        parts.append("--sign")
        parts.append("'\(identity)'")
        parts.append("'\(appPath)'")

        let command = parts.joined(separator: " ")
        let result: ProcessResult
        do {
            result = try process.runShell(command, cwd: nil)
        } catch {
            throw SigningError.processFailed(
                command: command,
                underlying: String(describing: error)
            )
        }

        guard result.exitCode == 0 else {
            throw SigningError.nonZeroExit(
                exitCode: result.exitCode,
                stderrTail: String(result.stderr.suffix(500))
            )
        }
    }
}
