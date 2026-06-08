/// Surfaces the build-command execution model. `relios build`/`release` run the
/// build command, so on an untrusted project that is arbitrary code execution.
///
///   - argv form (`[build].executable`) → ok (no shell)
///   - neither executable nor command   → fail (nothing to run)
///   - shell `command` + `allow_shell`  → ok (acknowledged)
///   - shell `command` (default)        → warn (review it; it runs via /bin/sh
///     and can execute SwiftPM plugins / Xcode run-script phases / anything)
public struct BuildTrustRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let build = context.spec.build

        if build.usesArgv {
            return .ok(title: "build uses argv (no shell)", code: DiagnosticCode("BUILD_TRUST_OK"))
        }
        if build.command.isEmpty {
            return .fail(
                title: "no build command",
                reason: "[build] has neither `executable` nor `command`",
                fix: "Set [build].executable + arguments (preferred), or [build].command",
                code: DiagnosticCode("BUILD_COMMAND_MISSING")
            )
        }
        if build.allowShell {
            return .ok(title: "build shell command (allow_shell)", code: DiagnosticCode("BUILD_TRUST_OK"))
        }
        return .warn(
            title: "build runs a shell command",
            reason: "[build].command runs via /bin/sh and executes arbitrary code (SwiftPM plugins, Xcode run-script phases, etc.)",
            fix: "Prefer [build].executable + arguments, or set [build].allow_shell = true to acknowledge",
            code: DiagnosticCode("BUILD_SHELL_COMMAND")
        )
    }
}
