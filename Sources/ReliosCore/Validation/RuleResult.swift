/// The verdict a single `ValidationRule` produces against a `ValidationContext`.
///
/// Each case carries its own `title` so a single rule can return different
/// titles for different failure modes (e.g. SpecValidityRule reports
/// "app.name is empty" vs "bundle_id is empty" depending on which check failed).
///
/// `Doctor` consumes every result; `Release.preflight` short-circuits on
/// the first `.fail`.
public enum RuleResult: Sendable, Equatable {
    case ok(title: String, code: DiagnosticCode)
    case warn(title: String, reason: String, fix: String, code: DiagnosticCode)
    case fail(title: String, reason: String, fix: String, code: DiagnosticCode)

    public var isFatal: Bool {
        if case .fail = self { return true }
        return false
    }

    /// The stable machine-readable identifier for this verdict.
    public var code: DiagnosticCode {
        switch self {
        case .ok(_, let code),
             .warn(_, _, _, let code),
             .fail(_, _, _, let code):
            return code
        }
    }

    public var severity: Severity {
        switch self {
        case .ok:   return .ok
        case .warn: return .warn
        case .fail: return .fail
        }
    }

    public var title: String {
        switch self {
        case .ok(let title, _),
             .warn(let title, _, _, _),
             .fail(let title, _, _, _):
            return title
        }
    }

    public var reason: String? {
        switch self {
        case .ok: return nil
        case .warn(_, let reason, _, _), .fail(_, let reason, _, _): return reason
        }
    }

    public var fix: String? {
        switch self {
        case .ok: return nil
        case .warn(_, _, let fix, _), .fail(_, _, let fix, _): return fix
        }
    }
}
