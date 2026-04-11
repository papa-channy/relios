import XCTest
import ReliosCore
import ReliosSupport

/// Gates 2, 3, 6: backup creation, rotation, and skip-when-no-app.
final class BackupManagerTests: XCTestCase {

    // Gate 2: creates zip of existing app
    func test_gate2_createsBackupZipWhenAppExists() throws {
        let fs = InMemoryFileSystem(files: [
            "/Applications/MyApp.app/Contents/MacOS/MyApp": "binary",
        ])
        let archiver = MockArchiveWriter()
        archiver.fs = fs
        let manager = BackupManager(fs: fs, archiver: archiver)

        let zip = try manager.backup(
            installedAppPath: "/Applications/MyApp.app",
            backupDir: "dist/app-backups",
            keepBackups: 3,
            appName: "MyApp",
            version: "1.2.3",
            build: "17"
        )

        XCTAssertEqual(zip, "dist/app-backups/MyApp-v1.2.3-b17.zip")
        XCTAssertEqual(archiver.calls.count, 1)
        XCTAssertEqual(archiver.calls[0].source, "/Applications/MyApp.app")
        XCTAssertEqual(archiver.calls[0].destination, "dist/app-backups/MyApp-v1.2.3-b17.zip")
    }

    // Gate 3: prunes old backups beyond keep_backups
    func test_gate3_prunesOldBackupsBeyondKeepCount() throws {
        let fs = InMemoryFileSystem(files: [
            "/Applications/MyApp.app/Contents/MacOS/MyApp": "binary",
            "dist/app-backups/MyApp-v1.0.0-b1.zip": "old1",
            "dist/app-backups/MyApp-v1.0.1-b1.zip": "old2",
            "dist/app-backups/MyApp-v1.0.2-b1.zip": "old3",
        ])
        let archiver = MockArchiveWriter()
        archiver.fs = fs
        let manager = BackupManager(fs: fs, archiver: archiver)

        _ = try manager.backup(
            installedAppPath: "/Applications/MyApp.app",
            backupDir: "dist/app-backups",
            keepBackups: 2,
            appName: "MyApp",
            version: "1.0.3",
            build: "1"
        )

        // After backup: 4 zips total, keep 2 → oldest 2 pruned
        let remaining = try fs.listDirectory(at: "dist/app-backups").filter { $0.hasSuffix(".zip") }
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains("MyApp-v1.0.2-b1.zip"))
        XCTAssertTrue(remaining.contains("MyApp-v1.0.3-b1.zip"))
    }

    // Gate 6: returns nil when no existing app
    func test_gate6_returnsNilWhenNoExistingApp() throws {
        let fs = InMemoryFileSystem()
        let archiver = MockArchiveWriter()
        let manager = BackupManager(fs: fs, archiver: archiver)

        let zip = try manager.backup(
            installedAppPath: "/Applications/MyApp.app",
            backupDir: "dist/app-backups",
            keepBackups: 3,
            appName: "MyApp",
            version: "1.0.0",
            build: "1"
        )

        XCTAssertNil(zip, "should return nil when there's nothing to back up")
        XCTAssertEqual(archiver.calls.count, 0, "should not invoke archiver")
    }
}
