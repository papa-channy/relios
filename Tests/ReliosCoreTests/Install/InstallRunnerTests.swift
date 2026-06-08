import XCTest
import ReliosCore
import ReliosSupport

/// Standalone `install` command: install the already-built .app without
/// rebuilding, bumping, or re-signing.
final class InstallRunnerTests: XCTestCase {

    private func makeSpec() -> ReleaseSpec {
        TestSpecBuilder.spec(signingMode: .adhoc)
    }

    /// pgrep returns 1 (not found) so terminate resolves to wasNotRunning fast.
    private func makeProcess() -> MockProcessRunner {
        let p = MockProcessRunner(result: .success)
        p.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        return p
    }

    /// Seeds a filesystem with a built .app, a version source, and (optionally)
    /// an already-installed app at the install path.
    private func makeFS(withExistingInstall: Bool) -> InMemoryFileSystem {
        var files: [String: String] = [
            "/proj/dist/X.app/Contents/MacOS/X": "new-binary",
            "/proj/X.swift": "v = \"1.2.3\"\nb = \"4\"",
        ]
        if withExistingInstall {
            files["/Applications/X.app/Contents/MacOS/X"] = "old-binary"
        }
        return InMemoryFileSystem(files: files)
    }

    // Installs the built .app, backs up the existing one, writes the manifest.
    func test_installsBuiltApp_backsUp_andWritesManifest() throws {
        let fs = makeFS(withExistingInstall: true)
        let process = makeProcess()
        let runner = InstallRunner(fs: fs, process: process)

        let result = try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: false,
            noOpen: false
        )

        XCTAssertEqual(result.bundlePath, "/proj/dist/X.app")
        XCTAssertEqual(result.installedAt, "/Applications/X.app")
        XCTAssertEqual(result.version, "1.2.3")
        XCTAssertEqual(result.build, "4")
        XCTAssertNotNil(result.backupPath, "should back up the existing app")
        XCTAssertTrue(result.launched)

        // Installed app is present, manifest written.
        XCTAssertTrue(fs.fileExists(at: "/Applications/X.app"))
        XCTAssertTrue(fs.fileExists(at: "/proj/dist/releases/latest.json"))

        // ditto archive (backup) and open (launch) were invoked.
        XCTAssertTrue(process.calls.contains { $0.command.contains("ditto -c -k") })
        XCTAssertTrue(process.calls.contains { $0.command.contains("/usr/bin/open") })
    }

    // No .app at output_path → clear, typed error (nothing was built).
    func test_throwsWhenNoBuiltApp() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/X.swift": "v = \"1.0.0\"\nb = \"1\"",
        ])
        let runner = InstallRunner(fs: fs, process: makeProcess())

        XCTAssertThrowsError(try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: false,
            noOpen: true
        )) { error in
            guard let e = error as? InstallError else { return XCTFail("wrong type") }
            if case .appNotFound = e { /* ok */ } else {
                XCTFail("expected .appNotFound, got \(e)")
            }
        }
    }

    // --skip-backup: no backup zip created, no ditto archive call.
    func test_skipBackup_doesNotArchive() throws {
        let fs = makeFS(withExistingInstall: true)
        let process = makeProcess()
        let runner = InstallRunner(fs: fs, process: process)

        let result = try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: true,
            noOpen: true
        )

        XCTAssertNil(result.backupPath)
        XCTAssertFalse(process.calls.contains { $0.command.contains("ditto -c -k") })
    }

    // No existing install → nothing to back up, backupPath is nil but install proceeds.
    func test_noExistingInstall_backupPathNil() throws {
        let fs = makeFS(withExistingInstall: false)
        let runner = InstallRunner(fs: fs, process: makeProcess())

        let result = try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: false,
            noOpen: true
        )

        XCTAssertNil(result.backupPath)
        XCTAssertTrue(fs.fileExists(at: "/Applications/X.app"))
    }

    // --no-open: app is installed but not launched.
    func test_noOpen_doesNotLaunch() throws {
        let fs = makeFS(withExistingInstall: false)
        let process = makeProcess()
        let runner = InstallRunner(fs: fs, process: process)

        let result = try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: true,
            noOpen: true
        )

        XCTAssertFalse(result.launched)
        XCTAssertFalse(process.calls.contains { $0.command.contains("/usr/bin/open") })
    }

    // --install-path override is honored over [install].path.
    func test_installPathOverride() throws {
        let fs = makeFS(withExistingInstall: false)
        let runner = InstallRunner(fs: fs, process: makeProcess())

        let result = try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: "/tmp/Custom.app",
            skipBackup: true,
            noOpen: true
        )

        XCTAssertEqual(result.installedAt, "/tmp/Custom.app")
        XCTAssertTrue(fs.fileExists(at: "/tmp/Custom.app"))
    }

    // Unreadable version source → typed error (patterns don't match).
    func test_throwsWhenVersionUnreadable() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/dist/X.app/Contents/MacOS/X": "binary",
            "/proj/X.swift": "no version here",
        ])
        let runner = InstallRunner(fs: fs, process: makeProcess())

        XCTAssertThrowsError(try runner.run(
            spec: makeSpec(),
            projectRoot: "/proj",
            installPathOverride: nil,
            skipBackup: true,
            noOpen: true
        )) { error in
            guard let e = error as? InstallError else { return XCTFail("wrong type") }
            if case .versionReadFailed = e { /* ok */ } else {
                XCTFail("expected .versionReadFailed, got \(e)")
            }
        }
    }
}
