import ReliosSupport

/// Checks that the build command's primary executable (`swift`) is available.
public struct BuildReadinessRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let process = context.process else {
            return .ok(title: "build readiness (skipped — no process runner)")
        }
        let result: ProcessResult
        do {
            result = try process.runShell("which swift", cwd: nil)
        } catch {
            return .fail(
                title: "swift not available",
                reason: "Could not check for swift: \(error)",
                fix: "Install Swift toolchain or run `xcode-select --install`"
            )
        }
        guard result.exitCode == 0 else {
            return .fail(
                title: "swift not found",
                reason: "`swift` is not in PATH",
                fix: "Install Swift toolchain or run `xcode-select --install`"
            )
        }
        return .ok(title: "build command available")
    }
}
