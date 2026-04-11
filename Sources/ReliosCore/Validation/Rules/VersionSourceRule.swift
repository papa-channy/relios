import ReliosSupport

/// Checks that [version].source_file exists AND both version/build patterns
/// match at least once. Uses `VersionSourceReader` read-only.
///
/// This rule is the fix for the false-ready problem: before this rule,
/// `doctor` said "ready" even when `AppVersion.swift` didn't exist,
/// causing `release` to fail at version-read step.
public struct VersionSourceRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let spec = context.spec
        let path = context.projectRoot + "/" + spec.version.sourceFile

        guard context.fs.fileExists(at: path) else {
            return .fail(
                title: "version source file missing",
                reason: "\(spec.version.sourceFile) not found at \(path)",
                fix: "Create the file or update [version].source_file in relios.toml"
            )
        }

        let reader = VersionSourceReader(fs: context.fs)
        do {
            _ = try reader.read(spec: spec.version, at: path)
        } catch let error as VersionSourceError {
            return .fail(
                title: "version source unreadable",
                reason: error.shortReason,
                fix: error.shortFix
            )
        } catch {
            return .fail(
                title: "version source error",
                reason: String(describing: error),
                fix: "Check [version] section in relios.toml"
            )
        }

        return .ok(title: "version source is readable")
    }
}
