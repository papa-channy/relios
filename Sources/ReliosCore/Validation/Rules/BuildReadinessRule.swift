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
        let fixHint: String
        switch context.spec.project.type {
        case .swiftpm:
            tool = "swift"
            fixHint = "Install Xcode Command Line Tools: `xcode-select --install`"
        case .xcodebuild:
            tool = "xcodebuild"
            fixHint = "Install Xcode from the Mac App Store, then run `sudo xcode-select --switch /Applications/Xcode.app`. Command Line Tools alone do not include xcodebuild."
        }

        let result: ProcessResult
        do {
            result = try process.runShell("which \(tool)", cwd: nil)
        } catch {
            return .fail(
                title: "\(tool) not available",
                reason: "Could not check for \(tool): \(error)",
                fix: fixHint
            )
        }
        guard result.exitCode == 0 else {
            return .fail(
                title: "\(tool) not found",
                reason: "`\(tool)` is not in PATH",
                fix: fixHint
            )
        }
        return .ok(title: "build tool available (\(tool))")
    }
}
