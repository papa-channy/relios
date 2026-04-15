import ReliosSupport

/// Skipped when `[dmg]` is absent or disabled. Otherwise warns if
/// `dmgbuild` is not on PATH — without it `relios dmg` cannot run.
///
/// Warn (not fail) because DMG is an optional output; the rest of the
/// release pipeline still works even if DMG cannot be produced.
public struct DMGReadinessRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let dmg = context.spec.dmg, dmg.enabled else {
            return .ok(title: "dmg check skipped (disabled)")
        }
        guard let process = context.process else {
            return .ok(title: "dmg check skipped (no process runner)")
        }

        let result: ProcessResult
        do {
            result = try process.runShell("command -v dmgbuild", cwd: nil)
        } catch {
            return .warn(
                title: "dmgbuild check failed",
                reason: "Could not check for dmgbuild: \(error)",
                fix: "Install it: `pip install dmgbuild` (or `pipx install dmgbuild`)"
            )
        }
        guard result.exitCode == 0 else {
            return .warn(
                title: "dmgbuild not found",
                reason: "`dmgbuild` is not in PATH; `relios dmg` will fail until it is installed",
                fix: "Install it: `pip install dmgbuild` (or `pipx install dmgbuild`)"
            )
        }
        return .ok(title: "dmgbuild available")
    }
}
