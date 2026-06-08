/// A safe, automatic fix that `relios doctor --fix` can apply.
///
/// Mirrors `ValidationRule`: each fix takes a uniform `ValidationContext`,
/// decides whether it applies, and—if so—performs a single safe mutation.
/// "Safe" means: idempotent, reversible-or-additive, and never destructive
/// (a fix creates a missing directory; it never deletes or overwrites user
/// content). A fix that doesn't apply returns `nil` so the runner can skip it.
public protocol DoctorFix: Sendable {
    func apply(_ context: ValidationContext) -> FixResult?
}

/// Outcome of attempting a single `DoctorFix`.
public struct FixResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case fixed
        case failed
    }

    public let status: Status
    public let title: String
    public let detail: String

    public init(status: Status, title: String, detail: String) {
        self.status = status
        self.title = title
        self.detail = detail
    }

    public static func fixed(_ title: String, _ detail: String) -> FixResult {
        FixResult(status: .fixed, title: title, detail: detail)
    }

    public static func failed(_ title: String, _ detail: String) -> FixResult {
        FixResult(status: .failed, title: title, detail: detail)
    }
}

/// Runs an ordered list of `DoctorFix`es and collects the ones that applied.
///
/// Fixes that return `nil` (nothing to do) are omitted from the result, so an
/// empty array means "nothing needed fixing."
public struct DoctorFixer: Sendable {
    private let fixes: [any DoctorFix]

    public init(fixes: [any DoctorFix]) {
        self.fixes = fixes
    }

    public func run(_ context: ValidationContext) -> [FixResult] {
        fixes.compactMap { $0.apply(context) }
    }
}
