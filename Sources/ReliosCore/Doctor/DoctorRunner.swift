/// Runs an ordered list of `ValidationRule`s against a `ValidationContext`
/// and converts each result into a `Diagnostic`.
///
/// v1 is intentionally trivial: no parallelism, no rule grouping, no
/// auto-fix dispatch. The CLI passes a hard-coded rule list and prints
/// the resulting diagnostics in order.
public struct DoctorRunner: Sendable {
    private let rules: [any ValidationRule]

    public init(rules: [any ValidationRule]) {
        self.rules = rules
    }

    public func run(_ context: ValidationContext) -> [Diagnostic] {
        rules.map { rule in
            Self.translate(rule.evaluate(context))
        }
    }

    // MARK: - private

    private static func translate(_ result: RuleResult) -> Diagnostic {
        switch result {
        case .ok(let title):
            return Diagnostic(status: .ok, title: title, reason: nil, fix: nil)
        case .warn(let title, let reason, let fix):
            return Diagnostic(status: .warn, title: title, reason: reason, fix: fix)
        case .fail(let title, let reason, let fix):
            return Diagnostic(status: .fail, title: title, reason: reason, fix: fix)
        }
    }
}
