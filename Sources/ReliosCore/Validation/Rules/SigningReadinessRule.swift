import ReliosSupport

/// Preflight check for the signing phase:
///   - `codesign` is on PATH (all modes except `keep`)
///   - when `mode == developer-id`: `identity` + `team_id` are set in the
///     spec, and the identity exists in the user's keychain.
public struct SigningReadinessRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let signing = context.spec.signing

        if signing.mode == .keep {
            return .ok(title: "signing skipped (keep mode)", code: DiagnosticCode("SIGNING_OK"))
        }

        if let toolCheck = checkCodesignAvailable(context) {
            return toolCheck
        }

        switch signing.mode {
        case .adhoc, .keep:
            return .ok(title: "signing tool available (codesign)", code: DiagnosticCode("SIGNING_OK"))

        case .developerID:
            guard let identity = signing.identity, !identity.isEmpty else {
                return .fail(
                    title: "signing.identity missing",
                    reason: "mode = \"developer-id\" requires [signing].identity",
                    fix: "Run `relios signing setup` or set signing.identity in relios.toml",
                    code: DiagnosticCode("SIGNING_IDENTITY_UNSET")
                )
            }
            guard let teamID = signing.teamID, !teamID.isEmpty else {
                return .fail(
                    title: "signing.team_id missing",
                    reason: "mode = \"developer-id\" requires [signing].team_id",
                    fix: "Run `relios signing setup` or set signing.team_id in relios.toml",
                    code: DiagnosticCode("SIGNING_TEAM_ID_UNSET")
                )
            }
            return checkIdentityInKeychain(identity: identity, teamID: teamID, context: context)
        }
    }

    /// `nil` = codesign found (or process unavailable, skipped), non-nil = fail.
    private func checkCodesignAvailable(_ context: ValidationContext) -> RuleResult? {
        guard let process = context.process else { return nil }
        let result: ProcessResult
        do {
            result = try process.runShell("which codesign", cwd: nil)
        } catch {
            return .fail(
                title: "codesign not available",
                reason: "Could not check for codesign: \(error)",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`",
                code: DiagnosticCode("CODESIGN_NOT_FOUND")
            )
        }
        guard result.exitCode == 0 else {
            return .fail(
                title: "codesign not found",
                reason: "`codesign` is not in PATH",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`",
                code: DiagnosticCode("CODESIGN_NOT_FOUND")
            )
        }
        return nil
    }

    private func checkIdentityInKeychain(
        identity: String,
        teamID: String,
        context: ValidationContext
    ) -> RuleResult {
        guard let process = context.process else {
            return .ok(title: "identity check skipped (no process runner)", code: DiagnosticCode("SIGNING_OK"))
        }
        let command = "security find-identity -v -p codesigning"
        let result: ProcessResult
        do {
            result = try process.runShell(command, cwd: nil)
        } catch {
            return .fail(
                title: "could not query keychain",
                reason: "security find-identity failed: \(error)",
                fix: "Ensure macOS keychain is accessible",
                code: DiagnosticCode("SIGNING_KEYCHAIN_ERROR")
            )
        }

        guard result.exitCode == 0 else {
            return .fail(
                title: "security find-identity failed",
                reason: "exit \(result.exitCode)",
                fix: "Run `security find-identity -v -p codesigning` manually",
                code: DiagnosticCode("SIGNING_KEYCHAIN_ERROR")
            )
        }

        // `security find-identity` prints lines like:
        //   1) ABCD...1234 "Developer ID Application: Chan (ABCDE12345)"
        // Match on identity name OR team ID — either one is enough to
        // confirm the cert is present. We check both so a user who typed
        // the identity inexactly but has the right team still passes.
        let haystack = result.stdout
        if haystack.contains(identity) || haystack.contains("(\(teamID))") {
            return .ok(title: "developer-id identity present in keychain", code: DiagnosticCode("SIGNING_IDENTITY_OK"))
        }
        return .fail(
            title: "signing identity not found in keychain",
            reason: "neither \"\(identity)\" nor team \(teamID) appeared in `security find-identity`",
            fix: "Import the cert: `relios signing import <path-to.p12>` or install via Xcode",
            code: DiagnosticCode("SIGNING_IDENTITY_NOT_FOUND")
        )
    }
}
