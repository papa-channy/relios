import XCTest
import ReliosCore
import ReliosSupport

final class RecoverRunnerTests: XCTestCase {

    private func spec() -> ReleaseSpec {
        TestSpecBuilder.spec(signingMode: .adhoc)   // install path /Applications/X.app
    }

    private func runner(_ fs: InMemoryFileSystem, alive: Set<Int32> = [], pid: Int32 = 100, host: String = "h1") -> RecoverRunner {
        RecoverRunner(fs: fs, liveness: FakeLiveness(alive: alive), pid: pid, hostname: host)
    }

    func test_cleanWhenNothingPresent() {
        let fs = InMemoryFileSystem()
        let report = runner(fs).scan(spec: spec(), projectRoot: "/proj")
        XCTAssertTrue(report.clean)
        XCTAssertNil(report.lockHolder)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func test_staleLockDetectedAndRemoved() throws {
        let fs = InMemoryFileSystem()
        // a dead-pid lock on this host
        try ProjectLock(fs: fs, liveness: FakeLiveness(alive: [999]), pid: 999, hostname: "h1")
            .acquire(command: "release", projectRoot: "/proj")

        let r = runner(fs, alive: [])   // 999 not alive → stale
        let report = r.scan(spec: spec(), projectRoot: "/proj")
        XCTAssertTrue(report.lockStale)
        XCTAssertTrue(report.findings.contains { $0.action == .removeStaleLock })

        _ = r.recover(spec: spec(), projectRoot: "/proj", dryRun: false)
        XCTAssertFalse(fs.fileExists(at: "/proj/.relios/lock"))
    }

    func test_liveLockIsNotStale() throws {
        let fs = InMemoryFileSystem()
        try ProjectLock(fs: fs, liveness: FakeLiveness(alive: [555]), pid: 555, hostname: "h1")
            .acquire(command: "release", projectRoot: "/proj")
        let report = runner(fs, alive: [555]).scan(spec: spec(), projectRoot: "/proj")
        XCTAssertFalse(report.lockStale)
        XCTAssertFalse(report.findings.contains { $0.action == .removeStaleLock })
    }

    func test_scratchLeftoverRemoved() {
        let fs = InMemoryFileSystem(directories: ["/Applications/.relios-rollback-scratch"])
        let r = runner(fs)
        XCTAssertTrue(r.scan(spec: spec(), projectRoot: "/proj").findings.contains { $0.action == .removeScratch })
        _ = r.recover(spec: spec(), projectRoot: "/proj", dryRun: false)
        XCTAssertFalse(fs.isDirectory(at: "/Applications/.relios-rollback-scratch"))
    }

    func test_stashWithInstallPresentIsRemoved() throws {
        let fs = InMemoryFileSystem(files: [
            "/Applications/X.app/Contents/MacOS/X": "current",
            "/Applications/X.app.relios-rollback-old/Contents/MacOS/X": "old",
        ])
        let r = runner(fs)
        XCTAssertTrue(r.scan(spec: spec(), projectRoot: "/proj").findings.contains { $0.action == .removeLeftoverStash })
        _ = r.recover(spec: spec(), projectRoot: "/proj", dryRun: false)
        XCTAssertFalse(fs.fileExists(at: "/Applications/X.app.relios-rollback-old"))
        XCTAssertTrue(fs.fileExists(at: "/Applications/X.app"), "current install preserved")
    }

    func test_stashWithInstallMissingIsRestored() throws {
        // install was moved aside but the move-into-place never happened.
        let fs = InMemoryFileSystem(files: [
            "/Applications/X.app.relios-old/Contents/MacOS/X": "stashed",
        ])
        let r = runner(fs)
        XCTAssertTrue(r.scan(spec: spec(), projectRoot: "/proj").findings.contains { $0.action == .restoreStash })
        _ = r.recover(spec: spec(), projectRoot: "/proj", dryRun: false)
        XCTAssertTrue(fs.fileExists(at: "/Applications/X.app"), "stash restored to install path")
        XCTAssertFalse(fs.fileExists(at: "/Applications/X.app.relios-old"))
    }

    func test_dryRunChangesNothing() {
        let fs = InMemoryFileSystem(directories: ["/Applications/.relios-rollback-scratch"])
        let findings = runner(fs).recover(spec: spec(), projectRoot: "/proj", dryRun: true)
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(fs.isDirectory(at: "/Applications/.relios-rollback-scratch"), "dry-run must not change anything")
    }
}
