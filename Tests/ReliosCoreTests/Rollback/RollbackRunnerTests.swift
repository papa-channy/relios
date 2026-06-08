import XCTest
import ReliosCore
import ReliosSupport

/// Rollback is crash-safe: it extracts to a scratch dir and only replaces the
/// current install via a stash-and-move that restores on failure.
final class RollbackRunnerTests: XCTestCase {

    private func loadSpec(from fs: InMemoryFileSystem) throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    // pgrep → 1 (not running); ditto -x simulated to create the scratch app.
    private func makeProcess(fs: InMemoryFileSystem, dittoSucceeds: Bool = true) -> MockProcessRunner {
        let p = MockProcessRunner(result: .success)
        p.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        if dittoSucceeds {
            // Simulate ditto -x extracting the .app into the scratch dir.
            p.sideEffects["ditto -x"] = {
                try? fs.writeUTF8("bin", to: "/Applications/.relios-rollback-scratch/PortfolioManager.app/Contents/MacOS/PortfolioManager")
            }
        } else {
            p.commandOverrides["ditto -x"] = ProcessResult(exitCode: 1, stdout: "", stderr: "corrupt")
        }
        return p
    }

    func test_restoresFromLatestBackup() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "dist/app-backups/PortfolioManager-v1.0.0-b1.zip": "old",
            "dist/app-backups/PortfolioManager-v1.0.1-b1.zip": "newer",
        ])
        let spec = try loadSpec(from: fs)
        let process = makeProcess(fs: fs)
        let result = try RollbackRunner(fs: fs, process: process).run(
            spec: spec, projectRoot: "/proj", specificBackup: nil, noOpen: true
        )

        XCTAssertEqual(result.restoredFrom, "dist/app-backups/PortfolioManager-v1.0.1-b1.zip")
        XCTAssertEqual(result.installedAt, "/Applications/PortfolioManager.app")
        XCTAssertTrue(fs.fileExists(at: "/Applications/PortfolioManager.app"), "restored app should be in place")
        XCTAssertFalse(fs.isDirectory(at: "/Applications/.relios-rollback-scratch"), "scratch should be cleaned up")
        XCTAssertTrue(process.calls.contains { $0.command.contains("ditto -x -k") && $0.command.contains("v1.0.1") })
    }

    func test_usesSpecificBackupWhenProvided() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "dist/app-backups/PortfolioManager-v1.0.0-b1.zip": "specific",
        ])
        let spec = try loadSpec(from: fs)
        let result = try RollbackRunner(fs: fs, process: makeProcess(fs: fs)).run(
            spec: spec, projectRoot: "/proj",
            specificBackup: "dist/app-backups/PortfolioManager-v1.0.0-b1.zip", noOpen: true
        )
        XCTAssertEqual(result.restoredFrom, "dist/app-backups/PortfolioManager-v1.0.0-b1.zip")
    }

    // CRASH-SAFETY: a failed extraction must leave the current install intact.
    func test_failedExtractionLeavesCurrentInstallIntact() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "dist/app-backups/PortfolioManager-v1.0.0-b1.zip": "zip",
            // an existing, working install we must NOT lose
            "/Applications/PortfolioManager.app/Contents/MacOS/PortfolioManager": "CURRENT",
        ])
        let spec = try loadSpec(from: fs)
        let process = makeProcess(fs: fs, dittoSucceeds: false)

        XCTAssertThrowsError(try RollbackRunner(fs: fs, process: process).run(
            spec: spec, projectRoot: "/proj", specificBackup: nil, noOpen: true
        )) { error in
            guard let e = error as? RollbackError else { return XCTFail("wrong type") }
            if case .unzipFailed = e { /* ok */ } else { XCTFail("expected .unzipFailed, got \(e)") }
        }

        // The current install is untouched — its original contents survive.
        XCTAssertEqual(
            try fs.readUTF8(at: "/Applications/PortfolioManager.app/Contents/MacOS/PortfolioManager"),
            "CURRENT",
            "a failed rollback must not damage the existing install"
        )
    }

    func test_throwsWhenNoBackupsExist() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": SampleTOMLs.fullSample])
        let spec = try loadSpec(from: fs)
        XCTAssertThrowsError(try RollbackRunner(fs: fs, process: makeProcess(fs: fs)).run(
            spec: spec, projectRoot: "/proj", specificBackup: nil, noOpen: true
        )) { error in
            guard case .noBackupsFound = (error as? RollbackError) else { return XCTFail("expected .noBackupsFound") }
        }
    }

    func test_throwsWhenSpecificBackupNotFound() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": SampleTOMLs.fullSample])
        let spec = try loadSpec(from: fs)
        XCTAssertThrowsError(try RollbackRunner(fs: fs, process: makeProcess(fs: fs)).run(
            spec: spec, projectRoot: "/proj", specificBackup: "/nope.zip", noOpen: true
        )) { error in
            guard case .backupNotFound = (error as? RollbackError) else { return XCTFail("expected .backupNotFound") }
        }
    }
}
