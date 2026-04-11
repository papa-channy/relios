import ReliosSupport

/// Runs `codesign --force --sign - <path>` (ad-hoc signing) via the
/// injected `ProcessRunner`.
///
/// v1 only supports `signing.mode = "adhoc"`. Developer ID and notarization
/// are explicitly out of scope.
public struct AdhocSigner: Sendable {
    private let process: any ProcessRunner

    public init(process: any ProcessRunner) {
        self.process = process
    }

    /// Signs the bundle at `appPath` ad-hoc. Throws `SigningError` on failure.
    public func sign(appPath: String) throws {
        let command = "codesign --force --deep --sign - '\(appPath)'"
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
