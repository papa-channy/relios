public enum InstallError: Error, Equatable {
    case backupFailed(reason: String)
    case terminateFailed(reason: String)
    case installFailed(reason: String)
    case launchFailed(reason: String)
    /// The standalone `install` command found no .app to install at
    /// `[bundle].output_path` (nothing has been built yet).
    case appNotFound(path: String)
    /// The standalone `install` command could not read the version source,
    /// which it needs for backup naming and the release manifest.
    case versionReadFailed(reason: String)
    /// The install/output path failed a safety check (not a .app, a protected
    /// target, or output == install).
    case unsafePath(reason: String)
}

extension InstallError {
    public var code: DiagnosticCode {
        switch self {
        case .backupFailed:      return DiagnosticCode("BACKUP_FAILED")
        case .terminateFailed:   return DiagnosticCode("TERMINATE_FAILED")
        case .installFailed:     return DiagnosticCode("INSTALL_FAILED")
        case .launchFailed:      return DiagnosticCode("LAUNCH_FAILED")
        case .appNotFound:       return DiagnosticCode("INSTALL_APP_NOT_FOUND")
        case .versionReadFailed: return DiagnosticCode("VERSION_SOURCE_READ_FAILED")
        case .unsafePath:        return DiagnosticCode("PATH_INSTALL_UNSAFE")
        }
    }

    public var shortReason: String {
        switch self {
        case .backupFailed(let r),
             .terminateFailed(let r),
             .installFailed(let r),
             .launchFailed(let r),
             .versionReadFailed(let r),
             .unsafePath(let r):
            return r
        case .appNotFound(let path):
            return "No .app found at \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .backupFailed:
            return "Check [install].backup_dir permissions or use --skip-backup"
        case .terminateFailed:
            return "Manually quit the app and re-run"
        case .installFailed:
            return "Check [install].path permissions"
        case .launchFailed:
            return "Manually open the app from /Applications"
        case .appNotFound:
            return "Run `relios release` (or `swift build`) first to produce the .app"
        case .versionReadFailed:
            return "Run `relios doctor` to check [version] patterns against the source file"
        case .unsafePath:
            return "Fix [install].path / [bundle].output_path — run `relios doctor`"
        }
    }
}
