public enum InstallError: Error, Equatable {
    case backupFailed(reason: String)
    case terminateFailed(reason: String)
    case installFailed(reason: String)
    case launchFailed(reason: String)
}

extension InstallError {
    public var shortReason: String {
        switch self {
        case .backupFailed(let r),
             .terminateFailed(let r),
             .installFailed(let r),
             .launchFailed(let r):
            return r
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
        }
    }
}
