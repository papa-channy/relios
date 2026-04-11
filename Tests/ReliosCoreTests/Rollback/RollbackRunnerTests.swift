import XCTest
import ReliosCore
import ReliosSupport

/// Gates 1-5 for rollback.
final class RollbackRunnerTests: XCTestCase {

    private func loadSpec(from fs: InMemoryFileSystem) throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    private func makeProcess() -> MockProcessRunner {
        // pgrep returns 1 (not found) so terminate succeeds immediately
        let p = MockProcessRunner(result: .success)
        p.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        return p
    }

    // Gate 1: finds latest backup and restores
    func test_gate1_restoresFromLatestBackup() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "dist/app-backups/PortfolioManager-v1.0.0-b1.zip": "old-zip",
            "dist/app-backups/PortfolioManager-v1.0.1-b1.zip": "newer-zip",
        ])
        let spec = try loadSpec(from: fs)
        let process = makeProcess()
        let runner = RollbackRunner(fs: fs, process: process)
        let result = try runner.run(
            spec: spec,
            projectRoot: "/proj",
            specificBackup: nil,
            noOpen: true
        )

        // Should pick the latest (alphabetically last) zip
        XCTAssertEqual(result.restoredFrom, "dist/app-backups/PortfolioManager-v1.0.1-b1.zip")
        XCTAssertEqual(result.installedAt,  "/Applications/PortfolioManager.app")

        // ditto -x -k was called with the right args
        XCTAssertTrue(
            process.calls.contains(where: {
                $0.command.contains("ditto -x -k") &&
                $0.command.contains("PortfolioManager-v1.0.1-b1.zip")
            }),
            "should invoke ditto to extract the backup"
        )
    }

    // Gate 2: --to overrides to specific backup
    func test_gate2_usesSpecificBackupWhenProvided() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "dist/app-backups/PortfolioManager-v1.0.0-b1.zip": "specific-zip",
        ])
        let spec = try loadSpec(from: fs)
        let process = makeProcess()
        let runner = RollbackRunner(fs: fs, process: process)
        let result = try runner.run(
            spec: spec,
            projectRoot: "/proj",
            specificBackup: "dist/app-backups/PortfolioManager-v1.0.0-b1.zip",
            noOpen: true
        )

        XCTAssertEqual(result.restoredFrom, "dist/app-backups/PortfolioManager-v1.0.0-b1.zip")
    }

    // Gate 3: no backups → clear error
    func test_gate3_throwsWhenNoBackupsExist() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
        ])
        let spec = try loadSpec(from: fs)
        let runner = RollbackRunner(fs: fs, process: makeProcess())

        XCTAssertThrowsError(try runner.run(
            spec: spec,
            projectRoot: "/proj",
            specificBackup: nil,
            noOpen: true
        )) { error in
            guard let e = error as? RollbackError else { return XCTFail("wrong type") }
            if case .noBackupsFound = e { /* ok */ } else {
                XCTFail("expected .noBackupsFound, got \(e)")
            }
        }
    }

    // Gate 3b: --to with nonexistent file → clear error
    func test_gate3_throwsWhenSpecificBackupNotFound() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
        ])
        let spec = try loadSpec(from: fs)
        let runner = RollbackRunner(fs: fs, process: makeProcess())

        XCTAssertThrowsError(try runner.run(
            spec: spec,
            projectRoot: "/proj",
            specificBackup: "/nonexistent.zip",
            noOpen: true
        )) { error in
            guard let e = error as? RollbackError else { return XCTFail("wrong type") }
            if case .backupNotFound = e { /* ok */ } else {
                XCTFail("expected .backupNotFound, got \(e)")
            }
        }
    }

    // Gate 5: dry-run invariant — rollback is a separate command, not part of
    // the release pipeline, so it doesn't affect dry-run. This is verified by
    // the existing test_c5_gate8 in ReleasePipelineTests remaining green.
}
