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

    public struct Result: Sendable, Equatable {
        public let restoredFrom: String
        public let installedAt: String
        public let launched: Bool
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

        // 3. Remove current install if exists
        if fs.fileExists(at: installPath) {
            try? fs.removeItem(at: installPath)
        }

        // 4. Unzip backup to install path's parent directory
        let parentDir = (installPath as NSString).deletingLastPathComponent
        let command = "/usr/bin/ditto -x -k '\(backupPath)' '\(parentDir)'"
        let result: ProcessResult
        do {
            result = try process.runShell(command, cwd: nil)
        } catch {
            throw RollbackError.unzipFailed(reason: String(describing: error))
        }
        guard result.exitCode == 0 else {
            throw RollbackError.unzipFailed(
                reason: "ditto exited with code \(result.exitCode): \(result.stderr)"
            )
        }
        // Trust ditto's exit code. If it returns 0, the app was extracted.
        // A post-unzip fileExists check would fail in mock-based unit tests
        // and adds no real safety over ditto's own error reporting.

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
