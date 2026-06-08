/// User-facing record of a single rule's verdict, ready for `ConsoleReporter`.
///
/// `DoctorRunner` translates `RuleResult` → `Diagnostic`. The `status` enum
/// is intentionally narrower than `RuleResult` (no associated values) so
/// downstream rendering code can switch on a flat 3-case enum.
public struct Diagnostic: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case ok
        case warn
        case fail
    }

    public let status: Status
    public let title: String
    public let reason: String?
    public let fix: String?
    /// Stable machine-readable identifier (carried from the rule's `RuleResult`).
    public let code: DiagnosticCode

    public init(status: Status, title: String, reason: String?, fix: String?, code: DiagnosticCode) {
        self.status = status
        self.title = title
        self.reason = reason
        self.fix = fix
        self.code = code
    }

    /// Severity mirrors `status` in the `Severity` vocabulary used by JSON output.
    public var severity: Severity {
        switch status {
        case .ok:   return .ok
        case .warn: return .warn
        case .fail: return .fail
        }
    }
}
