import XCTest
import ReliosCore
import ReliosSupport

/// Gates 3 + 4: VersionSourceRule correctly reports pass/fail for
/// the version source file state.
final class VersionSourceRuleTests: XCTestCase {

    private let canonicalAppVersion = """
    enum AppVersion {
        static let current = "0.1.0"
        static let build = "1"
    }
    """

    // MARK: - Gate 3 partial: source exists + patterns match → .ok

    func test_gate3_passesWhenSourceFileExistsAndPatternsMatch() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": """
            enum AppVersion {
                static let current = "1.2.3"
                static let build = "17"
            }
            """,
        ])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)

        let result = VersionSourceRule().evaluate(context)

        if case .ok(let title) = result {
            XCTAssertEqual(title, "version source readable")
        } else {
            XCTFail("expected .ok, got \(result)")
        }
    }

    // MARK: - Gate 4: source missing → .fail with clear reason/fix

    func test_gate4_failsWhenSourceFileMissing() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            // NO AppVersion.swift
        ])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)

        let result = VersionSourceRule().evaluate(context)

        if case .fail(let title, let reason, let fix) = result {
            XCTAssertEqual(title, "version source file missing")
            XCTAssertTrue(reason.contains("DesignMe/App/AppVersion.swift"),
                          "reason should mention the configured source file")
            XCTAssertTrue(fix.contains("source_file"),
                          "fix should point user to [version].source_file")
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    // MARK: - pattern doesn't match → .fail

    func test_failsWhenVersionPatternDoesNotMatch() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": "// empty, no patterns",
        ])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)

        let result = VersionSourceRule().evaluate(context)

        if case .fail(let title, _, _) = result {
            XCTAssertEqual(title, "version source unreadable")
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }
}
