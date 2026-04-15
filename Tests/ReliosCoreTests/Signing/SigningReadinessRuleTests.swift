import XCTest
import ReliosCore
import ReliosSupport

final class SigningReadinessRuleTests: XCTestCase {

    // MARK: helpers

    private func spec(
        mode: SigningSection.Mode,
        identity: String? = nil,
        teamID: String? = nil
    ) -> ReleaseSpec {
        return TestSpecBuilder.spec(signingMode: mode, identity: identity, teamID: teamID)
    }

    private func context(
        for spec: ReleaseSpec,
        process: any ProcessRunner
    ) -> ValidationContext {
        return ValidationContext(
            spec: spec,
            projectRoot: "/proj",
            fs: InMemoryFileSystem(files: [:]),
            process: process
        )
    }

    // MARK: tests

    func test_keepMode_skipsEverything() {
        let rule = SigningReadinessRule()
        let ctx = context(for: spec(mode: .keep), process: MockProcessRunner(result: .success))
        guard case .ok = rule.evaluate(ctx) else { return XCTFail("expected ok") }
    }

    func test_developerID_failsIfIdentityMissing() {
        let rule = SigningReadinessRule()
        let ctx = context(for: spec(mode: .developerID), process: MockProcessRunner(result: .success))
        guard case .fail(let title, _, _) = rule.evaluate(ctx) else {
            return XCTFail("expected fail")
        }
        XCTAssertTrue(title.contains("identity"))
    }

    func test_developerID_failsIfTeamIDMissing() {
        let rule = SigningReadinessRule()
        let ctx = context(
            for: spec(mode: .developerID, identity: "Developer ID Application: Chan (ABCDE12345)"),
            process: MockProcessRunner(result: .success)
        )
        // identity present but teamID explicitly nil — rule checks both.
        guard case .fail(let title, _, _) = rule.evaluate(ctx) else {
            return XCTFail("expected fail")
        }
        XCTAssertTrue(title.contains("team_id"))
    }

    func test_developerID_passesWhenIdentityInKeychain() {
        let rule = SigningReadinessRule()
        let process = MockProcessRunner(result: .success)
        process.commandOverrides["security find-identity"] = ProcessResult(
            exitCode: 0,
            stdout: "1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 \"Developer ID Application: Chan (ABCDE12345)\"",
            stderr: ""
        )
        let ctx = context(
            for: spec(mode: .developerID,
                      identity: "Developer ID Application: Chan (ABCDE12345)",
                      teamID: "ABCDE12345"),
            process: process
        )
        guard case .ok = rule.evaluate(ctx) else { return XCTFail("expected ok") }
    }

    func test_developerID_failsWhenIdentityNotInKeychain() {
        let rule = SigningReadinessRule()
        let process = MockProcessRunner(result: .success)
        process.commandOverrides["security find-identity"] = ProcessResult(
            exitCode: 0,
            stdout: "0 identities found",
            stderr: ""
        )
        let ctx = context(
            for: spec(mode: .developerID,
                      identity: "Developer ID Application: Chan (ABCDE12345)",
                      teamID: "ABCDE12345"),
            process: process
        )
        guard case .fail = rule.evaluate(ctx) else { return XCTFail("expected fail") }
    }
}
