/// Domain error for `relios update generate`.
public enum UpdateError: Error, Equatable {
    case updateDisabled
    case versionReadFailed(reason: String)
    /// No `--download-url` was given and the template couldn't be resolved
    /// because `--repo`/`--asset` were missing.
    case downloadURLUnresolved(reason: String)
    case writeFailed(path: String, underlying: String)
}

extension UpdateError {
    public var code: DiagnosticCode {
        switch self {
        case .updateDisabled:        return DiagnosticCode("UPDATE_DISABLED")
        case .versionReadFailed:     return DiagnosticCode("VERSION_SOURCE_READ_FAILED")
        case .downloadURLUnresolved: return DiagnosticCode("UPDATE_DOWNLOAD_URL_UNRESOLVED")
        case .writeFailed:           return DiagnosticCode("UPDATE_WRITE_FAILED")
        }
    }

    public var shortReason: String {
        switch self {
        case .updateDisabled:
            return "[update] is absent or disabled in relios.toml"
        case .versionReadFailed(let r):
            return r
        case .downloadURLUnresolved(let r):
            return r
        case .writeFailed(let path, _):
            return "Could not write update manifest to \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .updateDisabled:
            return "Add `[update]\\nenabled = true` to relios.toml"
        case .versionReadFailed:
            return "Run `relios doctor` to check [version] patterns against the source file"
        case .downloadURLUnresolved:
            return "Pass --download-url, or pass --repo and --asset so the URL template can resolve"
        case .writeFailed:
            return "Check write permissions for [update].output_dir"
        }
    }
}
