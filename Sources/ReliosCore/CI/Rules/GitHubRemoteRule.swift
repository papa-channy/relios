/// Verifies that the project is a git repo with a `github.com` remote.
/// The release workflow publishes a GitHub Release — without a GitHub
/// remote, pushing a tag cannot trigger the workflow at all.
///
/// Implementation reads `.git/config` directly instead of shelling out to
/// `git`, so the rule stays usable when `git` is not on `PATH` (rare in
/// practice, but it also keeps unit tests pure-filesystem).
public struct GitHubRemoteRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let configPath = context.projectRoot + "/.git/config"
        guard context.fs.fileExists(at: configPath) else {
            return .warn(
                title: "git repo",
                reason: "Not a git repository (\(context.projectRoot))",
                fix: "Run `git init` and add a GitHub remote before pushing tags"
            )
        }

        let config = (try? context.fs.readUTF8(at: configPath)) ?? ""
        guard config.contains("github.com") else {
            return .warn(
                title: "github remote",
                reason: "No github.com remote found in .git/config",
                fix: "Add a GitHub remote: `git remote add origin https://github.com/<you>/<repo>.git`"
            )
        }

        return .ok(title: "github remote present")
    }
}
