import Foundation
import ReliosSupport

/// Restores a previously backed-up .app to the install path.
///
/// Flow:
///   1. Find the backup zip (latest in backup_dir, or --to override)
///   2. Terminate running app (if applicable)
///   3. Remove current install
///   4. Unzip backup to install path
///   5. Optionally launch
public struct RollbackRunner: Sendable {
    private let fs: any FileSystem
    private let process: any ProcessRunner

    public init(fs: any FileSystem, process: any ProcessRunner) {
        self.fs = fs
        self.process = process
    }

    public struct Result: Sendable, Equatable, Encodable {
        public let restoredFrom: String
        public let installedAt: String
        public let launched: Bool

        private enum CodingKeys: String, CodingKey {
            case restoredFrom = "restored_from"
            case installedAt = "installed_at"
            case launched
        }
    }

    public func run(
        spec: ReleaseSpec,
        projectRoot: String,
        specificBackup: String?,
        noOpen: Bool
    ) throws -> Result {
        // 1. Find backup
        let backupDir = spec.install.backupDir
        let backupPath: String
        if let specific = specificBackup {
            guard fs.fileExists(at: specific) else {
                throw RollbackError.backupNotFound(path: specific)
            }
            backupPath = specific
        } else {
            backupPath = try findLatestBackup(in: backupDir)
        }

        let installPath = spec.install.path

        // 2. Terminate running app
        if spec.install.quitRunningApp {
            let terminator = RunningAppTerminator(process: process)
            do {
                _ = try terminator.terminate(
                    bundleId: spec.app.bundleId,
                    installedAppPath: installPath,
                    executableName: spec.app.name
                )
            } catch {
                throw RollbackError.terminateFailed(
                    reason: String(describing: error)
                )
            }
        }

        // Refuse to operate on a protected path (/, $HOME, project root).
        if PathSafety.isDangerousTarget(installPath, projectRoot: projectRoot, homeDir: NSHomeDirectory()) {
            throw RollbackError.unsafeArchive(reason: "refusing to replace protected path \(installPath)")
        }

        let parentDir = (installPath as NSString).deletingLastPathComponent
        let appName = (installPath as NSString).lastPathComponent

        // 3. Extract the backup into a scratch dir first — the current install
        //    is NOT touched until we have a validated replacement. This is what
        //    makes rollback crash-safe: a failed/corrupt/unsafe extraction
        //    leaves the existing app intact.
        let scratch = parentDir + "/.relios-rollback-scratch"
        try? fs.removeItem(at: scratch)
        do {
            let result = try process.runShell("/usr/bin/ditto -x -k '\(backupPath)' '\(scratch)'", cwd: nil)
            guard result.exitCode == 0 else {
                try? fs.removeItem(at: scratch)
                throw RollbackError.unzipFailed(reason: "ditto exited with code \(result.exitCode): \(result.stderr)")
            }
        } catch let e as RollbackError {
            throw e
        } catch {
            try? fs.removeItem(at: scratch)
            throw RollbackError.unzipFailed(reason: String(describing: error))
        }

        // Zip-slip guard: every extracted entry must stay within scratch, and
        // no top-level entry may be a symlink.
        let entries = (try? fs.listDirectory(at: scratch)) ?? []
        do {
            try PathSafety.assertExtractionWithin(entries, targetDir: scratch)
        } catch {
            try? fs.removeItem(at: scratch)
            throw RollbackError.unsafeArchive(reason: "archive escapes the extraction directory")
        }
        for entry in entries where fs.isSymlink(at: scratch + "/" + entry) {
            try? fs.removeItem(at: scratch)
            throw RollbackError.unsafeArchive(reason: "archive contains a symlink: \(entry)")
        }

        let extractedApp = scratch + "/" + appName
        guard fs.fileExists(at: extractedApp) else {
            try? fs.removeItem(at: scratch)
            throw RollbackError.unzipFailed(reason: "backup did not contain \(appName)")
        }

        // 4. Atomic-ish replace: stash the current install aside, move the
        //    restored app into place, restore the stash if the move fails.
        let stash = installPath + ".relios-rollback-old"
        try? fs.removeItem(at: stash)
        let hadCurrent = fs.fileExists(at: installPath)
        if hadCurrent {
            do {
                try fs.moveItem(from: installPath, to: stash)
            } catch {
                try? fs.removeItem(at: scratch)
                throw RollbackError.installFailed(reason: "could not stash current install: \(error)")
            }
        }
        do {
            try fs.moveItem(from: extractedApp, to: installPath)
        } catch {
            if hadCurrent { try? fs.moveItem(from: stash, to: installPath) }
            try? fs.removeItem(at: scratch)
            throw RollbackError.installFailed(reason: "could not move restored app into place: \(error)")
        }
        if hadCurrent { try? fs.removeItem(at: stash) }
        try? fs.removeItem(at: scratch)

        // 5. Optionally launch
        var launched = false
        if spec.install.autoOpen && !noOpen {
            let launcher = AppLauncher(process: process)
            try? launcher.launch(appPath: installPath)
            launched = true
        }

        return Result(
            restoredFrom: backupPath,
            installedAt: installPath,
            launched: launched
        )
    }

    // MARK: - private

    private func findLatestBackup(in dir: String) throws -> String {
        guard fs.isDirectory(at: dir) else {
            throw RollbackError.noBackupsFound(dir: dir)
        }
        let entries: [String]
        do {
            entries = try fs.listDirectory(at: dir)
                .filter { $0.hasSuffix(".zip") }
                .sorted()
        } catch {
            throw RollbackError.noBackupsFound(dir: dir)
        }
        guard let latest = entries.last else {
            throw RollbackError.noBackupsFound(dir: dir)
        }
        return dir + "/" + latest
    }
}
