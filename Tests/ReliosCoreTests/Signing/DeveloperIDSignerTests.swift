import XCTest
import ReliosCore
import ReliosSupport

final class DeveloperIDSignerTests: XCTestCase {

    func test_invokesCodesignWithIdentityAndHardenedRuntime() throws {
        let process = MockProcessRunner(result: .success)
        let signer = DeveloperIDSigner(process: process)

        try signer.sign(
            appPath: "/proj/dist/MyApp.app",
            identity: "Developer ID Application: Chan (ABCDE12345)",
            hardenedRuntime: true,
            entitlementsPath: nil
        )

        XCTAssertEqual(process.calls.count, 1)
        let cmd = process.calls[0].command
        XCTAssertTrue(cmd.contains("codesign"))
        XCTAssertTrue(cmd.contains("--force"))
        XCTAssertTrue(cmd.contains("--timestamp"))
        XCTAssertTrue(cmd.contains("--options runtime"), "hardened runtime must emit --options runtime")
        XCTAssertTrue(cmd.contains("--sign 'Developer ID Application: Chan (ABCDE12345)'"))
        XCTAssertTrue(cmd.contains("/proj/dist/MyApp.app"))
        XCTAssertFalse(cmd.contains("--sign -"), "must not use ad-hoc identity")
    }

    func test_omitsHardenedRuntimeWhenFalse() throws {
        let process = MockProcessRunner(result: .success)
        let signer = DeveloperIDSigner(process: process)

        try signer.sign(
            appPath: "/a.app",
            identity: "ID",
            hardenedRuntime: false,
            entitlementsPath: nil
        )

        XCTAssertFalse(process.calls[0].command.contains("--options runtime"))
    }

    func test_includesEntitlementsWhenProvided() throws {
        let process = MockProcessRunner(result: .success)
        let signer = DeveloperIDSigner(process: process)

        try signer.sign(
            appPath: "/a.app",
            identity: "ID",
            hardenedRuntime: true,
            entitlementsPath: "/ent/app.entitlements"
        )

        XCTAssertTrue(process.calls[0].command.contains("--entitlements '/ent/app.entitlements'"))
    }

    func test_throwsNonZeroExit() {
        let process = MockProcessRunner(result: ProcessResult(exitCode: 1, stdout: "", stderr: "bad id"))
        let signer = DeveloperIDSigner(process: process)

        XCTAssertThrowsError(try signer.sign(
            appPath: "/a.app",
            identity: "ID",
            hardenedRuntime: true,
            entitlementsPath: nil
        )) { error in
            guard let e = error as? SigningError,
                  case .nonZeroExit(let code, _) = e else {
                return XCTFail("expected .nonZeroExit, got \(error)")
            }
            XCTAssertEqual(code, 1)
        }
    }
}
