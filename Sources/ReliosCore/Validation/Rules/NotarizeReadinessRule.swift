import Foundation
import ReliosSupport

/// Preflight for `relios notarize`:
///   - `[notarize]` absent or disabled → skipped
///   - `xcrun notarytool` missing → fail (Xcode 13+ required)
///   - `signing.mode != .developer-id` → fail (notarization requires DevID)
///   - credentials missing from env → warn locally (CI resolves via secrets)
///   - APPLE_TEAM_ID in env vs [signing].team_id disagree → warn
public struct NotarizeReadinessRule: ValidationRule {
    private let env: [String: String]

    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        self.env = env
    }

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let notarize = context.spec.notarize, notarize.enabled else {
            return .ok(title: "notarize check skipped (disabled)")
        }

        // Hard requirement: Developer ID signing.
        if context.spec.signing.mode != .developerID {
            return .fail(
                title: "notarize requires developer-id signing",
                reason: "[notarize].enabled = true requires [signing].mode = \"developer-id\" (current: \"\(context.spec.signing.mode.rawValue)\")",
                fix: "Change [signing].mode to \"developer-id\" — notarization cannot be applied to ad-hoc binaries"
            )
        }

        // notarytool presence.
        if let process = context.process {
            let result = (try? process.runShell("xcrun notarytool --version", cwd: nil))
                ?? ProcessResult(exitCode: 1, stdout: "", stderr: "")
            guard result.exitCode == 0 else {
                return .fail(
                    title: "notarytool not available",
                    reason: "`xcrun notarytool` did not run (exit \(result.exitCode))",
                    fix: "Install Xcode 13+ (Command Line Tools alone don't include notarytool)"
                )
            }
        }

        // Credentials. Local runs often don't have these set — that's a
        // warn rather than fail, because CI supplies them via secrets.
        let missing = NotarizerCredentials.envVarNames
            .filter { (env[$0] ?? "").isEmpty }
        if !missing.isEmpty {
            return .warn(
                title: "notarize credentials not set locally",
                reason: "missing env: \(missing.joined(separator: ", "))",
                fix: "Set them before running `relios notarize`, or supply them via GitHub secrets in CI"
            )
        }

        // Team ID sanity check — only when we have both sides.
        if let specTeam = context.spec.signing.teamID,
           let envTeam = env["APPLE_TEAM_ID"],
           !envTeam.isEmpty,
           specTeam != envTeam {
            return .warn(
                title: "team_id mismatch",
                reason: "[signing].team_id (\(specTeam)) ≠ APPLE_TEAM_ID (\(envTeam))",
                fix: "Align the two — Apple rejects submissions where the signer's team differs from the submitter's"
            )
        }

        return .ok(title: "notarize ready")
    }
}
