public enum RollbackError: Error, Equatable {
    case noBackupsFound(dir: String)
    case backupNotFound(path: String)
    case unzipFailed(reason: String)
    case installFailed(reason: String)
    case terminateFailed(reason: String)
    /// The backup archive contains an entry that escapes the target dir or a
    /// symlink — refused to avoid zip-slip; or the target path is protected.
    case unsafeArchive(reason: String)
}

extension RollbackError {
    public var code: DiagnosticCode {
        switch self {
        case .noBackupsFound:  return DiagnosticCode("ROLLBACK_NO_BACKUPS")
        case .backupNotFound:  return DiagnosticCode("ROLLBACK_BACKUP_NOT_FOUND")
        case .unzipFailed:     return DiagnosticCode("ROLLBACK_UNZIP_FAILED")
        case .installFailed:   return DiagnosticCode("INSTALL_FAILED")
        case .terminateFailed: return DiagnosticCode("TERMINATE_FAILED")
        case .unsafeArchive:   return DiagnosticCode("ROLLBACK_UNSAFE_ARCHIVE")
        }
    }

    public var shortReason: String {
        switch self {
        case .noBackupsFound(let dir):
            return "No backup zips found in \(dir)"
        case .backupNotFound(let path):
            return "Backup file not found: \(path)"
        case .unzipFailed(let reason):
            return "Could not extract backup: \(reason)"
        case .installFailed(let reason):
            return "Could not restore app: \(reason)"
        case .terminateFailed(let reason):
            return "Could not terminate running app: \(reason)"
        case .unsafeArchive(let reason):
            return "Refused unsafe rollback: \(reason)"
        }
    }

    public var shortFix: String {
        switch self {
        case .noBackupsFound:
            return "Run `relios release` at least once with backup enabled"
        case .backupNotFound:
            return "Check the path or run `relios rollback` without --to to use the latest backup"
        case .unzipFailed:
            return "Check backup zip integrity"
        case .installFailed:
            return "Check [install].path permissions"
        case .terminateFailed:
            return "Manually quit the app and re-run"
        case .unsafeArchive:
            return "Use a trusted backup, or check [install].path"
        }
    }
}
