public enum RollbackError: Error, Equatable {
    case noBackupsFound(dir: String)
    case backupNotFound(path: String)
    case unzipFailed(reason: String)
    case installFailed(reason: String)
    case terminateFailed(reason: String)
}

extension RollbackError {
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
        }
    }
}
