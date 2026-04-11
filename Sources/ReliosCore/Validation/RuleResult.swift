/// The verdict a single `ValidationRule` produces against a `ValidationContext`.
///
/// Each case carries its own `title` so a single rule can return different
/// titles for different failure modes (e.g. SpecValidityRule reports
/// "app.name is empty" vs "bundle_id is empty" depending on which check failed).
///
/// `Doctor` consumes every result; `Release.preflight` short-circuits on
/// the first `.fail`.
public enum RuleResult: Sendable, Equatable {
    case ok(title: String)
    case warn(title: String, reason: String, fix: String)
    case fail(title: String, reason: String, fix: String)

    public var isFatal: Bool {
        if case .fail = self { return true }
        return false
    }
}
