import Foundation
import ReliosSupport

/// Backs up the currently installed .app to a zip in backup_dir,
/// enforcing keep_backups rotation.
public struct BackupManager: Sendable {
    private let fs: any FileSystem
    private let archiver: any ArchiveWriter

    public init(fs: any FileSystem, archiver: any ArchiveWriter) {
        self.fs = fs
        self.archiver = archiver
    }

    /// Creates a backup zip of `installedAppPath` in `backupDir`.
    /// Returns the path to the created zip, or nil if there was nothing to back up.
    /// After creation, prunes old backups to keep at most `keepBackups`.
    public func backup(
        installedAppPath: String,
        backupDir: String,
        keepBackups: Int,
        appName: String,
        version: String,
        build: String
    ) throws -> String? {
        // Nothing to back up if the app doesn't exist
        guard fs.fileExists(at: installedAppPath) else {
            return nil
        }

        try fs.createDirectory(at: backupDir)

        let zipName = "\(appName)-v\(version)-b\(build).zip"
        let zipPath = backupDir + "/" + zipName

        do {
            try archiver.writeArchive(source: installedAppPath, destination: zipPath)
        } catch {
            throw InstallError.backupFailed(
                reason: "Could not create backup at \(zipPath): \(error)"
            )
        }

        try pruneOldBackups(in: backupDir, keep: keepBackups)

        return zipPath
    }

    // MARK: - private

    private func pruneOldBackups(in dir: String, keep: Int) throws {
        guard keep > 0 else { return }
        let entries: [String]
        do {
            entries = try fs.listDirectory(at: dir)
                .filter { $0.hasSuffix(".zip") }
                .sorted() // alphabetical = chronological for our naming scheme
        } catch {
            return // non-fatal
        }
        if entries.count > keep {
            let toRemove = entries.prefix(entries.count - keep)
            for name in toRemove {
                try? fs.removeItem(at: dir + "/" + name)
            }
        }
    }
}
