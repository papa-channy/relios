/// Sanity-checks fields that decoded successfully but are semantically empty.
///
/// This rule is intentionally tiny in v1: it only checks the three fields
/// that an init-generated spec absolutely must populate. Deeper checks (real
/// bundle id format, min_macos parseability, etc.) belong in dedicated rules
/// added in later slices.
public struct SpecValidityRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let spec = context.spec

        if spec.app.name.isEmpty {
            return .fail(
                title: "app.name is empty",
                reason: "Application name must not be empty",
                fix: "Set [app].name in relios.toml"
            )
        }

        if spec.app.bundleId.isEmpty {
            return .fail(
                title: "bundle_id is empty",
                reason: "Bundle identifier is required",
                fix: "Set [app].bundle_id in relios.toml"
            )
        }

        if spec.project.binaryTarget.isEmpty {
            return .fail(
                title: "binary_target is empty",
                reason: "No executable target specified",
                fix: "Set [project].binary_target in relios.toml"
            )
        }

        return .ok(title: "spec valid")
    }
}
