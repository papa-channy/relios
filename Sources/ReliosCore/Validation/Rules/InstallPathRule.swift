import Foundation
import ReliosSupport

/// Checks that the install path's parent directory exists and is writable.
/// Returns `.warn` (not `.fail`) if the parent doesn't exist — it might be
/// created at release time, or the user might use `--install-path` to override.
public struct InstallPathRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let installPath = context.spec.install.path
        let parentDir = (installPath as NSString).deletingLastPathComponent

        guard context.fs.isDirectory(at: parentDir) else {
            return .warn(
                title: "install path parent missing",
                reason: "Directory \(parentDir) does not exist",
                fix: "Create the directory or update [install].path in relios.toml"
            )
        }

        return .ok(title: "install path writable")
    }
}
