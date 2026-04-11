public struct InstallSection: Decodable, Equatable, Sendable {
    public let path: String
    public let autoOpen: Bool
    public let backupDir: String
    public let keepBackups: Int
    public let quitRunningApp: Bool

    private enum CodingKeys: String, CodingKey {
        case path
        case autoOpen       = "auto_open"
        case backupDir      = "backup_dir"
        case keepBackups    = "keep_backups"
        case quitRunningApp = "quit_running_app"
    }
}
