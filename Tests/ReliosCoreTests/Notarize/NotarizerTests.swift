import XCTest
import ReliosCore
import ReliosSupport

final class NotarizerTests: XCTestCase {

    private let creds = NotarizerCredentials(
        appleID: "dev@example.com",
        password: "abcd-efgh",
        teamID: "ABCDE12345"
    )

    // MARK: - presence

    func test_failsWhenNotarytoolMissing() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.dmg": "x"])
        let runner = MockProcessRunner(result: .success)
        runner.commandOverrides["xcrun notarytool --version"] =
            ProcessResult(exitCode: 1, stdout: "", stderr: "no such xctool")
        let n = Notarizer(fs: fs, process: runner)

        XCTAssertThrowsError(try n.notarize(
            artifactPath: "/out/app.dmg",
            credentials: creds,
            timeoutSeconds: 60
        )) { err in
            XCTAssertEqual(err as? NotarizeError, .notarytoolNotFound)
        }
    }

    // MARK: - DMG path

    func test_dmgPathSubmitsThenStaplesTheDMG() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.dmg": "x"])
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 0,
            stdout: "status: Accepted",
            stderr: ""
        ))
        let n = Notarizer(fs: fs, process: runner)

        let output = try n.notarize(
            artifactPath: "/out/app.dmg",
            credentials: creds,
            timeoutSeconds: 120
        )

        XCTAssertEqual(output.stapledArtifactPath, "/out/app.dmg")
        // notarytool submit was called with the DMG path.
        let submitCall = runner.calls.first { $0.command.contains("notarytool submit") }
        XCTAssertNotNil(submitCall)
        XCTAssertTrue(submitCall!.command.contains("/out/app.dmg"))
        XCTAssertTrue(submitCall!.command.contains("--wait --timeout 120s"))

        // staple was called on the DMG directly (no unzip).
        let stapleCall = runner.calls.first { $0.command.contains("stapler staple") }
        XCTAssertNotNil(stapleCall)
        XCTAssertTrue(stapleCall!.command.contains("/out/app.dmg"))

        // validate at the end.
        XCTAssertTrue(runner.calls.contains { $0.command.contains("stapler validate") })

        // No ditto calls (no unzip/rezip for DMG).
        XCTAssertFalse(runner.calls.contains { $0.command.contains("ditto") })
    }

    // MARK: - ZIP path

    func test_zipPathUnzipsStaplesAppThenRepacks() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.zip": "x"])
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: 0,
            stdout: "status: Accepted",
            stderr: ""
        ))
        // Simulate ditto -x -k extracting an .app into the scratch dir.
        runner.sideEffects["ditto -x -k"] = {
            try? fs.createDirectory(at: "/out/_relios-staple/App.app")
        }
        let n = Notarizer(fs: fs, process: runner)

        let output = try n.notarize(
            artifactPath: "/out/app.zip",
            credentials: creds,
            timeoutSeconds: 300
        )

        XCTAssertEqual(output.stapledArtifactPath, "/out/app.zip")

        // ditto unzip used.
        XCTAssertTrue(runner.calls.contains {
            $0.command.contains("ditto -x -k") && $0.command.contains("/out/app.zip")
        })
        // staple was called on the inner .app, not the zip.
        XCTAssertTrue(runner.calls.contains {
            $0.command.contains("stapler staple") && $0.command.contains("/out/_relios-staple/App.app")
        })
        // ditto re-zip back to original path.
        XCTAssertTrue(runner.calls.contains {
            $0.command.contains("ditto -c -k") && $0.command.contains("/out/app.zip")
        })
    }

    // MARK: - submit failure

    func test_submissionStatusInvalidIsReportedEvenWithZeroExit() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.dmg": "x"])
        let runner = MockProcessRunner(result: .success)
        runner.commandOverrides["notarytool submit"] = ProcessResult(
            exitCode: 0,
            stdout: """
            Current status: Invalid
            See `notarytool log` for details.
            """,
            stderr: ""
        )
        let n = Notarizer(fs: fs, process: runner)

        XCTAssertThrowsError(try n.notarize(
            artifactPath: "/out/app.dmg",
            credentials: creds,
            timeoutSeconds: 60
        )) { err in
            guard case NotarizeError.submissionFailed = err else {
                return XCTFail("expected .submissionFailed, got \(err)")
            }
        }
    }

    func test_submissionNonZeroExitIsReported() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.dmg": "x"])
        let runner = MockProcessRunner(result: .success)
        runner.commandOverrides["notarytool submit"] = ProcessResult(
            exitCode: 2,
            stdout: "",
            stderr: "HTTP 401 Unauthorized"
        )
        let n = Notarizer(fs: fs, process: runner)

        XCTAssertThrowsError(try n.notarize(
            artifactPath: "/out/app.dmg",
            credentials: creds,
            timeoutSeconds: 60
        )) { err in
            guard case NotarizeError.submissionFailed(let code, let log) = err else {
                return XCTFail("expected .submissionFailed, got \(err)")
            }
            XCTAssertEqual(code, 2)
            XCTAssertTrue(log.contains("Unauthorized"))
        }
    }

    // MARK: - unsupported artifact

    func test_pkgArtifactRejectedAsUnsupported() throws {
        let fs = InMemoryFileSystem(files: ["/out/app.pkg": "x"])
        let runner = MockProcessRunner(result: .success)
        let n = Notarizer(fs: fs, process: runner)

        XCTAssertThrowsError(try n.notarize(
            artifactPath: "/out/app.pkg",
            credentials: creds,
            timeoutSeconds: 60
        )) { err in
            guard case NotarizeError.unsupportedArtifact = err else {
                return XCTFail("expected .unsupportedArtifact, got \(err)")
            }
        }
    }
}
