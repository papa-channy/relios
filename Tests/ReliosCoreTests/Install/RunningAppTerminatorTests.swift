import XCTest
import ReliosCore
import ReliosSupport

/// Gate 4: 3-step termination fallback.
final class RunningAppTerminatorTests: XCTestCase {

    // Gate 4: osascript succeeds → terminated via bundleId
    func test_gate4_terminatesViaBundleId() throws {
        // osascript succeeds, pgrep returns 1 (not found = app quit)
        let process = MockProcessRunner(queue: [
            .success,                                          // osascript
            ProcessResult(exitCode: 1, stdout: "", stderr: ""), // pgrep → not found
        ])
        let terminator = RunningAppTerminator(process: process)

        let outcome = try terminator.terminate(
            bundleId: "com.test.app",
            installedAppPath: "/Applications/TestApp.app",
            executableName: "TestApp"
        )

        XCTAssertEqual(outcome, .terminated(method: "bundleId"))
    }

    // Gate 4: osascript fails, pgrep finds it, pkill -f succeeds
    func test_gate4_fallsBackToPathKill() throws {
        let process = MockProcessRunner(queue: [
            .success,                                          // osascript
            ProcessResult(exitCode: 0, stdout: "", stderr: ""), // pgrep after osascript → still running
            .success,                                          // pkill -f
            ProcessResult(exitCode: 1, stdout: "", stderr: ""), // pgrep → not found
        ])
        let terminator = RunningAppTerminator(process: process)

        let outcome = try terminator.terminate(
            bundleId: "com.test.app",
            installedAppPath: "/Applications/TestApp.app",
            executableName: "TestApp"
        )

        XCTAssertEqual(outcome, .terminated(method: "installedPath"))
    }

    // App not running → wasNotRunning
    func test_wasNotRunningWhenOsascriptFailsAndPgrepFindsNothing() throws {
        // osascript returns non-zero (app not scriptable or not running),
        // pgrep returns 1 (not found)
        let process = MockProcessRunner(queue: [
            ProcessResult(exitCode: 1, stdout: "", stderr: ""),  // osascript
            ProcessResult(exitCode: 1, stdout: "", stderr: ""),  // pgrep → not found
        ])
        let terminator = RunningAppTerminator(process: process)

        let outcome = try terminator.terminate(
            bundleId: "com.test.app",
            installedAppPath: "/Applications/TestApp.app",
            executableName: "TestApp"
        )

        XCTAssertEqual(outcome, .wasNotRunning)
    }
}
