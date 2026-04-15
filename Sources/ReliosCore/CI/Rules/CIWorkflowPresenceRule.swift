/// Warns if `.github/workflows/ci.yml` is missing. Not fatal because the
/// PR/push CI gate is convenience — releases still work without it — but
/// the user opted into CI scaffolding, so we nudge them to complete it.
public struct CIWorkflowPresenceRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let path = context.projectRoot + "/.github/workflows/ci.yml"
        guard context.fs.fileExists(at: path) else {
            return .warn(
                title: "ci workflow missing",
                reason: ".github/workflows/ci.yml not found",
                fix: "Run `relios ci init` to regenerate (use --force if release.yml already exists)"
            )
        }
        return .ok(title: "ci workflow present")
    }
}
