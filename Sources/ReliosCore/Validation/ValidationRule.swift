/// Shared validation primitive for both `Doctor` and `Release.preflight`.
///
/// `associatedtype Input` was rejected in v1 because it forces type erasure
/// at every call site. Instead, every rule takes a uniform `ValidationContext`
/// and picks out the fields it needs.
public protocol ValidationRule: Sendable {
    func evaluate(_ context: ValidationContext) -> RuleResult
}
