import XCTest
import ReliosCore
import ReliosSupport

/// Gates 1-4 for the 3 new readiness rules.
final class ReadinessRuleTests: XCTestCase {

    // MARK: - Gate 1: BuildReadinessRule

    func test_gate1_buildReadiness_passesWhenSwiftAvailable() throws {
        let process = MockProcessRunner(result: .success)
        let context = makeContext(process: process)

        let result = BuildReadinessRule().evaluate(context)

        if case .ok(let title) = result {
            XCTAssertEqual(title, "build command available")
        } else {
            XCTFail("expected .ok, got \(result)")
        }
    }

    func test_gate1_buildReadiness_failsWhenSwiftNotFound() throws {
        let process = MockProcessRunner(result: .failure(exitCode: 1, stderr: ""))
        let context = makeContext(process: process)

        let result = BuildReadinessRule().evaluate(context)

        if case .fail(let title, _, let fix) = result {
            XCTAssertEqual(title, "swift not found")
            XCTAssertTrue(fix.contains("xcode-select"))
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    // MARK: - Gate 2: InstallPathRule

    func test_gate2_installPath_passesWhenParentExists() throws {
        // fullSample has install.path = "/Applications/PortfolioManager.app"
        // parent = "/Applications" — seed it as directory
        let fs = InMemoryFileSystem(
            files: ["/proj/relios.toml": SampleTOMLs.fullSample],
            directories: ["/Applications"]
        )
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)

        let result = InstallPathRule().evaluate(context)

        if case .ok(let title) = result {
            XCTAssertEqual(title, "install path is writable")
        } else {
            XCTFail("expected .ok, got \(result)")
        }
    }

    func test_gate2_installPath_warnsWhenParentMissing() throws {
        let fs = InMemoryFileSystem(
            files: ["/proj/relios.toml": SampleTOMLs.fullSample]
            // no /Applications directory
        )
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)

        let result = InstallPathRule().evaluate(context)

        if case .warn(let title, _, _) = result {
            XCTAssertEqual(title, "install path parent missing")
        } else {
            XCTFail("expected .warn, got \(result)")
        }
    }

    // MARK: - Gate 3: SigningReadinessRule

    func test_gate3_signingReadiness_passesWhenCodesignAvailable() throws {
        let process = MockProcessRunner(result: .success)
        let context = makeContext(process: process)

        let result = SigningReadinessRule().evaluate(context)

        if case .ok(let title) = result {
            XCTAssertEqual(title, "codesign available")
        } else {
            XCTFail("expected .ok, got \(result)")
        }
    }

    func test_gate3_signingReadiness_failsWhenCodesignNotFound() throws {
        let process = MockProcessRunner(result: .failure(exitCode: 1, stderr: ""))
        let context = makeContext(process: process)

        let result = SigningReadinessRule().evaluate(context)

        if case .fail(let title, _, let fix) = result {
            XCTAssertEqual(title, "codesign not found")
            XCTAssertTrue(fix.contains("xcode-select"))
        } else {
            XCTFail("expected .fail, got \(result)")
        }
    }

    // MARK: - Gate 4: all 5 rules run in doctor

    func test_gate4_doctorRunsFiveRules() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": """
            enum AppVersion {
                static let current = "1.2.3"
                static let build = "17"
            }
            """,
        ], directories: ["/Applications"])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let process = MockProcessRunner(result: .success)
        let context = ValidationContext(
            spec: spec,
            projectRoot: "/proj",
            fs: fs,
            process: process
        )

        let runner = DoctorRunner(rules: [
            SpecValidityRule(),
            VersionSourceRule(),
            BuildReadinessRule(),
            InstallPathRule(),
            SigningReadinessRule(),
        ])

        let diagnostics = runner.run(context)

        XCTAssertEqual(diagnostics.count, 5, "doctor should run exactly 5 rules")
        for d in diagnostics {
            XCTAssertEqual(d.status, .ok,
                           "diagnostic '\(d.title)' should be .ok but was \(d.status)")
        }
    }

    // MARK: - helpers

    private func makeContext(process: MockProcessRunner) -> ValidationContext {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
        ], directories: ["/Applications"])
        let spec = try! SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(
            spec: spec,
            projectRoot: "/proj",
            fs: fs,
            process: process
        )
    }
}
