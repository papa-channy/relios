import Foundation

/// Validates the `[update]` auto-update feed configuration.
///
/// Skipped (`.ok`) when `[update]` is absent or disabled — the feature is
/// opt-in. When enabled, warns about config that would produce an unusable
/// manifest: a download URL template missing its `{tag}`/`{asset}` placeholders
/// (which would otherwise bake a fixed URL into every release's manifest).
public struct UpdateReadinessRule: ValidationRule {
    private let env: [String: String]

    public init(env: [String: String] = ProcessInfo.processInfo.environment) {
        self.env = env
    }

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        guard let update = context.spec.update, update.enabled else {
            return .ok(title: "update check skipped (disabled)", code: DiagnosticCode("UPDATE_OK"))
        }

        let template = update.downloadURLTemplate
        let hasTag   = template.contains("{tag}")
        let hasAsset = template.contains("{asset}")

        if !hasTag || !hasAsset {
            var missing: [String] = []
            if !hasTag { missing.append("{tag}") }
            if !hasAsset { missing.append("{asset}") }
            return .warn(
                title: "update url template",
                reason: "[update].download_url_template is missing \(missing.joined(separator: ", "))",
                fix: "Include {repo}, {tag}, and {asset} placeholders, or pass --download-url explicitly in CI",
                code: DiagnosticCode("UPDATE_URL_TEMPLATE_INCOMPLETE")
            )
        }

        // Signed feed requested but no key available locally → warn (CI supplies
        // it via the RELIOS_UPDATE_SIGNING_KEY secret).
        if update.sign && (env["RELIOS_UPDATE_SIGNING_KEY"] ?? "").isEmpty {
            return .warn(
                title: "update signing key not set",
                reason: "[update].sign = true but RELIOS_UPDATE_SIGNING_KEY is not set",
                fix: "Run `relios update keygen`, set the key as a CI secret, or pass --signing-key-file",
                code: DiagnosticCode("UPDATE_SIGNING_KEY_MISSING")
            )
        }

        return .ok(title: "update feed configured", code: DiagnosticCode("UPDATE_OK"))
    }
}
