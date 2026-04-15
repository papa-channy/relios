/// Fails if `.github/workflows/release.yml` is missing. This is the
/// workflow `relios ci init` generates — without it, pushing a tag does
/// nothing.
public struct ReleaseWorkflowPresenceRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let path = context.projectRoot + "/.github/workflows/release.yml"
        guard context.fs.fileExists(at: path) else {
            return .fail(
                title: "release workflow missing",
                reason: ".github/workflows/release.yml not found",
                fix: "Run `relios ci init` to generate it"
            )
        }
        return .ok(title: "release workflow present")
    }
}
