/// Domain error for `VersionSourceReader`.
/// `ReleasePipeline` catches and translates to `ReleaseError.versionReadFailed`.
public enum VersionSourceError: Error, Equatable {
    case unreadable(path: String, underlying: String)
    case versionPatternUnmatched(path: String, pattern: String)
    case buildPatternUnmatched(path: String, pattern: String)
    case unparseableSemver(raw: String)
    case unparseableBuild(raw: String)
}

extension VersionSourceError {
    public var code: DiagnosticCode {
        switch self {
        case .unreadable:              return DiagnosticCode("VERSION_SOURCE_UNREADABLE")
        case .versionPatternUnmatched: return DiagnosticCode("VERSION_PATTERN_UNMATCHED")
        case .buildPatternUnmatched:   return DiagnosticCode("BUILD_PATTERN_UNMATCHED")
        case .unparseableSemver:       return DiagnosticCode("VERSION_UNPARSEABLE")
        case .unparseableBuild:        return DiagnosticCode("BUILD_NUMBER_UNPARSEABLE")
        }
    }

    public var shortReason: String {
        switch self {
        case .unreadable(let path, _):
            return "Version source file unreadable: \(path)"
        case .versionPatternUnmatched(let path, _):
            return "Version pattern did not match in \(path)"
        case .buildPatternUnmatched(let path, _):
            return "Build pattern did not match in \(path)"
        case .unparseableSemver(let raw):
            return "Could not parse semver: '\(raw)'"
        case .unparseableBuild(let raw):
            return "Could not parse build number: '\(raw)'"
        }
    }

    public var shortFix: String {
        switch self {
        case .unreadable:
            return "Check [version].source_file points at an existing file"
        case .versionPatternUnmatched:
            return "Check [version].version_pattern matches your source file"
        case .buildPatternUnmatched:
            return "Check [version].build_pattern matches your source file"
        case .unparseableSemver:
            return "Use MAJOR.MINOR.PATCH format (e.g. 1.2.3)"
        case .unparseableBuild:
            return "Use a non-negative integer for the build number"
        }
    }
}
