import XCTest
import ReliosCore
import ReliosSupport

/// Gate 7: launch behavior with auto_open on/off.
final class AppLauncherTests: XCTestCase {

    func test_gate7_launchCallsOpenWithAppPath() throws {
        let process = MockProcessRunner(result: .success)
        let launcher = AppLauncher(process: process)

        try launcher.launch(appPath: "/Applications/MyApp.app")

        XCTAssertEqual(process.calls.count, 1)
        XCTAssertTrue(process.calls[0].command.contains("/usr/bin/open"))
        XCTAssertTrue(process.calls[0].command.contains("/Applications/MyApp.app"))
    }

    func test_throwsOnOpenFailure() {
        let process = MockProcessRunner(result: .failure(exitCode: 1, stderr: "not found"))
        let launcher = AppLauncher(process: process)

        XCTAssertThrowsError(try launcher.launch(appPath: "/Applications/MyApp.app"))
    }
}
