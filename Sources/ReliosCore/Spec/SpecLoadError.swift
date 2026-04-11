/// Domain error for relios.toml load/parse failures.
/// Surfaced to the user via `ReliosError` (added in a later slice) — for now,
/// `SpecLoader` throws this directly and the CLI layer prints it.
public enum SpecLoadError: Error, Equatable {
    case missing(path: String)
    case unreadable(path: String, underlying: String)
    case malformed(path: String, underlying: String)
}

extension SpecLoadError {
    public var shortReason: String {
        switch self {
        case .missing(let path):
            return "relios.toml not found at \(path)"
        case .unreadable(let path, _):
            return "relios.toml is unreadable at \(path)"
        case .malformed(let path, _):
            return "relios.toml is malformed at \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .missing:
            return "Run `relios init` to generate a relios.toml"
        case .unreadable:
            return "Check file permissions on relios.toml"
        case .malformed:
            return "Validate TOML syntax — see error detail with --verbose"
        }
    }
}
