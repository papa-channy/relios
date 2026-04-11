import XCTest
import ReliosCore
import ReliosSupport

/// Gate 4: AdhocSigner calls codesign --force --sign - <path>.
final class AdhocSignerTests: XCTestCase {

    func test_gate4_invokesCodesignWithCorrectArguments() throws {
        let process = MockProcessRunner(result: .success)
        let signer = AdhocSigner(process: process)

        try signer.sign(appPath: "/proj/dist/MyApp.app")

        XCTAssertEqual(process.calls.count, 1)
        let cmd = process.calls[0].command
        XCTAssertTrue(cmd.contains("codesign"), "must invoke codesign")
        XCTAssertTrue(cmd.contains("--force"), "must use --force")
        XCTAssertTrue(cmd.contains("--sign -"), "must use ad-hoc identity")
        XCTAssertTrue(cmd.contains("/proj/dist/MyApp.app"), "must pass app path")
    }

    func test_throwsSigningErrorOnNonZeroExit() {
        let process = MockProcessRunner(result: ProcessResult(
            exitCode: 1, stdout: "", stderr: "codesign failed"
        ))
        let signer = AdhocSigner(process: process)

        XCTAssertThrowsError(try signer.sign(appPath: "/proj/dist/MyApp.app")) { error in
            guard let e = error as? SigningError else { return XCTFail("wrong type") }
            if case .nonZeroExit(let code, _) = e {
                XCTAssertEqual(code, 1)
            } else {
                XCTFail("expected .nonZeroExit, got \(e)")
            }
        }
    }
}
