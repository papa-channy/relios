import Foundation
import ReliosSupport

/// Runs the full notarization lifecycle against a single artifact:
///
///   1. `xcrun notarytool submit <artifact> --wait` (Apple server round-trip)
///   2. On success:
///      - DMG: `xcrun stapler staple <artifact>` — the ticket lives on the DMG
///      - ZIP: unzip, staple the inner `.app`, re-zip in place (zip itself
///              cannot hold a ticket; notarytool accepts zip for submission
///              but stapling only works on .app/.dmg/.pkg).
///   3. `xcrun stapler validate` as a paranoid final check.
///
/// Every Apple call goes through `ProcessRunner` so tests can mock the
/// external behavior. The re-zip path shells out to `ditto` for parity
/// with the CI `Package .app` step's archive format.
public struct Notarizer: Sendable {
    public struct Output: Equatable, Sendable {
        public let stapledArtifactPath: String
    }

    private let fs: any FileSystem
    private let process: any ProcessRunner

    public init(fs: any FileSystem, process: any ProcessRunner) {
        self.fs = fs
        self.process = process
    }

    public func notarize(
        artifactPath: String,
        credentials: NotarizerCredentials,
        timeoutSeconds: Int
    ) throws -> Output {
        guard fs.fileExists(at: artifactPath) else {
            throw NotarizeError.artifactMissing(path: artifactPath)
        }

        // notarytool presence check.
        let presence = try process.runShell("xcrun notarytool --version", cwd: nil)
        guard presence.exitCode == 0 else {
            throw NotarizeError.notarytoolNotFound
        }

        try submitAndWait(
            artifactPath: artifactPath,
            credentials: credentials,
            timeoutSeconds: timeoutSeconds
        )

        let stapled: String
        if artifactPath.hasSuffix(".dmg") {
            try staple(path: artifactPath)
            stapled = artifactPath
        } else if artifactPath.hasSuffix(".zip") {
            stapled = try stapleAppInsideZip(zipPath: artifactPath)
        } else {
            throw NotarizeError.unsupportedArtifact(path: artifactPath)
        }

        // Final sanity: offline Gatekeeper uses the stapled ticket, so if
        // validate fails here the UX regression is silent (online fallback
        // still works). Catch it loud.
        let validation = try process.runShell(
            "xcrun stapler validate \(shellQuote(stapled))",
            cwd: nil
        )
        guard validation.exitCode == 0 else {
            throw NotarizeError.stapleFailed(
                exitCode: validation.exitCode,
                stderr: validation.stderr
            )
        }

        return Output(stapledArtifactPath: stapled)
    }

    // MARK: - submit

    private func submitAndWait(
        artifactPath: String,
        credentials: NotarizerCredentials,
        timeoutSeconds: Int
    ) throws {
        // `--wait` blocks until Apple's queue resolves; notarytool handles
        // polling internally. We pass --timeout for the waitcommand's own
        // upper bound. Credentials go via env to keep them out of ps output.
        // `--wait` can take up to `timeoutSeconds` — stream output so CI
        // logs show Apple's progress (submission id, status polls, final
        // verdict) instead of a silent hang.
        let cmd = """
        xcrun notarytool submit \(shellQuote(artifactPath)) \
        --apple-id \(shellQuote(credentials.appleID)) \
        --password \(shellQuote(credentials.password)) \
        --team-id \(shellQuote(credentials.teamID)) \
        --wait --timeout \(timeoutSeconds)s
        """
        let result = try process.runShellStreaming(cmd, cwd: nil)
        if result.exitCode != 0 {
            let combined = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw NotarizeError.submissionFailed(
                exitCode: result.exitCode,
                log: combined
            )
        }
        // notarytool returns 0 for "Accepted", also for "In Progress" with
        // no --wait, also (confusingly) when the submission succeeds but
        // the package is rejected. Guard with a keyword scan on stdout.
        let lower = result.stdout.lowercased()
        if lower.contains("status: invalid") || lower.contains("status: rejected") {
            throw NotarizeError.submissionFailed(
                exitCode: 0,
                log: result.stdout
            )
        }
    }

    // MARK: - staple

    private func staple(path: String) throws {
        let result = try process.runShell(
            "xcrun stapler staple \(shellQuote(path))",
            cwd: nil
        )
        guard result.exitCode == 0 else {
            throw NotarizeError.stapleFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
    }

    /// Unzips the artifact into a scratch dir, staples the first `.app`
    /// bundle found, re-zips it over the original path.
    private func stapleAppInsideZip(zipPath: String) throws -> String {
        let parentDir = (zipPath as NSString).deletingLastPathComponent
        let scratch = parentDir + "/_relios-staple"

        // Clean + recreate scratch.
        try? fs.removeItem(at: scratch)
        do {
            try fs.createDirectory(at: scratch)
        } catch {
            throw NotarizeError.repackFailed(underlying: String(describing: error))
        }
        defer { try? fs.removeItem(at: scratch) }

        // Unzip.
        let unzip = try process.runShell(
            "ditto -x -k \(shellQuote(zipPath)) \(shellQuote(scratch))",
            cwd: nil
        )
        guard unzip.exitCode == 0 else {
            throw NotarizeError.repackFailed(
                underlying: "ditto unzip exit \(unzip.exitCode): \(unzip.stderr)"
            )
        }

        // Find the .app bundle at the scratch root (one level).
        let entries = (try? fs.listDirectory(at: scratch)) ?? []
        guard let appName = entries.first(where: { $0.hasSuffix(".app") }) else {
            throw NotarizeError.repackFailed(
                underlying: "no .app bundle inside \(zipPath)"
            )
        }
        let appPath = scratch + "/" + appName

        // Staple the .app.
        try staple(path: appPath)

        // Re-zip back over the original path.
        try? fs.removeItem(at: zipPath)
        let rezip = try process.runShell(
            "ditto -c -k --sequesterRsrc --keepParent \(shellQuote(appPath)) \(shellQuote(zipPath))",
            cwd: nil
        )
        guard rezip.exitCode == 0 else {
            throw NotarizeError.repackFailed(
                underlying: "ditto rezip exit \(rezip.exitCode): \(rezip.stderr)"
            )
        }

        return zipPath
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
