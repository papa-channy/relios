import XCTest
import ReliosCore
import ReliosSupport

/// Direct unit tests for `SpecValidityRule`.
/// `DoctorRunnerTests` covers the rule indirectly via the runner pipeline,
/// but these tests pin the exact title/reason/fix strings the rule emits.
final class SpecValidityRuleTests: XCTestCase {

    func test_passesOnFullSampleSpec() throws {
        let context = try makeContext(toml: SampleTOMLs.fullSample)
        let result = SpecValidityRule().evaluate(context)

        if case .ok(let title) = result {
            XCTAssertEqual(title, "spec is valid")
        } else {
            XCTFail("expected .ok, got \(result)")
        }
    }

    func test_failsWhenAppNameIsEmpty() throws {
        let toml = SampleTOMLs.fullSample.replacingOccurrences(
            of: #"name = "PortfolioManager""#,
            with: #"name = """#
        )
        let context = try makeContext(toml: toml)

        let result = SpecValidityRule().evaluate(context)

        if case .fail(let title, _, let fix) = result {
            XCTAssertEqual(title, "app.name is empty")
            XCTAssertEqual(fix, "Set [app].name in relios.toml")
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    func test_failsWhenBundleIdIsEmpty() throws {
        let toml = SampleTOMLs.fullSample.replacingOccurrences(
            of: #"bundle_id = "com.chan.portfolio-manager""#,
            with: #"bundle_id = """#
        )
        let context = try makeContext(toml: toml)

        let result = SpecValidityRule().evaluate(context)

        if case .fail(let title, _, _) = result {
            XCTAssertEqual(title, "bundle_id is empty")
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    func test_failsWhenBinaryTargetIsEmpty() throws {
        let toml = SampleTOMLs.fullSample.replacingOccurrences(
            of: #"binary_target = "PortfolioManager""#,
            with: #"binary_target = """#
        )
        let context = try makeContext(toml: toml)

        let result = SpecValidityRule().evaluate(context)

        if case .fail(let title, _, _) = result {
            XCTAssertEqual(title, "binary_target is empty")
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    // MARK: - helpers

    private func makeContext(toml: String) throws -> ValidationContext {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
    }
}
