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

    public init(status: Status, title: String, reason: String?, fix: String?) {
        self.status = status
        self.title = title
        self.reason = reason
        self.fix = fix
    }
}
