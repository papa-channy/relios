import ReliosSupport

/// Checks that the build command's primary executable is available.
/// For SwiftPM projects, checks `swift`. For xcodebuild projects,
/// checks `xcodebuild`.
public struct BuildReadinessRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let process = context.process else {
            return .ok(title: "build tool check skipped")
        }

        let tool: String
        switch context.spec.project.type {
        case .swiftpm:
            tool = "swift"
        case .xcodebuild:
            tool = "xcodebuild"
        }

        let result: ProcessResult
        do {
            result = try process.runShell("which \(tool)", cwd: nil)
        } catch {
            return .fail(
                title: "\(tool) not available",
                reason: "Could not check for \(tool): \(error)",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`"
            )
        }
        guard result.exitCode == 0 else {
            return .fail(
                title: "\(tool) not found",
                reason: "`\(tool)` is not in PATH",
                fix: "Install Xcode Command Line Tools: `xcode-select --install`"
            )
        }
        return .ok(title: "build tool available (\(tool))")
    }
}
