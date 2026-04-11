import ReliosSupport

/// Checks that `codesign` is available on the system.
public struct SigningReadinessRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let process = context.process else {
            return .ok(title: "signing readiness (skipped — no process runner)")
        }
        let result: ProcessResult
        do {
            result = try process.runShell("which codesign", cwd: nil)
        } catch {
            return .fail(
                title: "codesign not available",
                reason: "Could not check for codesign: \(error)",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`"
            )
        }
        guard result.exitCode == 0 else {
            return .fail(
                title: "codesign not found",
                reason: "`codesign` is not in PATH",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`"
            )
        }
        return .ok(title: "codesign available")
    }
}
