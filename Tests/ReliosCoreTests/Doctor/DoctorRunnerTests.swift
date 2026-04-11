import XCTest
import ReliosCore
import ReliosSupport

/// Locks the v1 doctor pipeline contract:
///   - 1 rule + 1 spec → exactly 1 diagnostic, in order
///   - rule order is preserved in diagnostic order
///   - status mapping (.ok/.warn/.fail) is faithful
final class DoctorRunnerTests: XCTestCase {

    func test_runsSingleRuleAndProducesOneDiagnostic() throws {
        let context = try makeContext(toml: SampleTOMLs.fullSample)
        let runner = DoctorRunner(rules: [SpecValidityRule()])

        let diagnostics = runner.run(context)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].status, .ok)
        XCTAssertEqual(diagnostics[0].title,  "spec is valid")
        XCTAssertNil(diagnostics[0].reason)
        XCTAssertNil(diagnostics[0].fix)
    }

    func test_runsMultipleRulesAndPreservesOrder() throws {
        let context = try makeContext(toml: SampleTOMLs.fullSample)
        let runner = DoctorRunner(rules: [
            FixedRule(result: .ok(title: "first")),
            FixedRule(result: .warn(title: "second", reason: "r", fix: "f")),
            FixedRule(result: .ok(title: "third")),
        ])

        let diagnostics = runner.run(context)

        XCTAssertEqual(diagnostics.map(\.title), ["first", "second", "third"])
        XCTAssertEqual(diagnostics.map(\.status), [.ok, .warn, .ok])
    }

    func test_translatesFailRuleToFailDiagnosticWithReasonAndFix() throws {
        // Empty bundle_id forces SpecValidityRule into a .fail branch.
        let toml = SampleTOMLs.fullSample.replacingOccurrences(
            of: #"bundle_id = "com.chan.portfolio-manager""#,
            with: #"bundle_id = """#
        )
        let context = try makeContext(toml: toml)
        let runner = DoctorRunner(rules: [SpecValidityRule()])

        let diagnostics = runner.run(context)

        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].status, .fail)
        XCTAssertEqual(diagnostics[0].title,  "bundle_id is empty")
        XCTAssertNotNil(diagnostics[0].reason)
        XCTAssertNotNil(diagnostics[0].fix)
    }

    // MARK: - helpers

    private func makeContext(toml: String) throws -> ValidationContext {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
    }
}

/// Inline fake rule used by the order-preservation test. Ignores its context.
private struct FixedRule: ValidationRule {
    let result: RuleResult
    func evaluate(_ context: ValidationContext) -> RuleResult { result }
}
