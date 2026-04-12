import XCTest
import ReliosCore
import ReliosSupport

final class XcodeProjectGuardRuleTests: XCTestCase {

    private let rule = XcodeProjectGuardRule()

    // MARK: - pass: no markers

    func test_passesWhenNoXcodeMarkersExist() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(files: [
                "/proj/Package.swift": "",
                "/proj/relios.toml": SampleTOMLs.fullSample,
            ])
        )

        let result = rule.evaluate(context)

        guard case .ok = result else {
            XCTFail("Expected .ok, got \(result)")
            return
        }
    }

    // MARK: - pass: markers + passthrough

    func test_passesWhenXcodeMarkersExistWithPassthroughMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.xcodebuildPassthrough,
            fs: InMemoryFileSystem(
                files: [
                    "/proj/relios.toml": SampleTOMLs.xcodebuildPassthrough,
                ],
                directories: ["/proj/MyXcodeApp.xcodeproj"]
            )
        )

        let result = rule.evaluate(context)

        guard case .ok(let title) = result else {
            XCTFail("Expected .ok, got \(result)")
            return
        }
        XCTAssertTrue(title.contains("passthrough"))
    }

    // MARK: - fail: markers + assembly

    func test_failsWhenXcodeprojExistsWithAssemblyMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(
                files: ["/proj/relios.toml": SampleTOMLs.fullSample],
                directories: ["/proj/MyApp.xcodeproj"]
            )
        )

        let result = rule.evaluate(context)

        guard case .fail(_, let reason, let fix) = result else {
            XCTFail("Expected .fail, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("MyApp.xcodeproj"))
        XCTAssertTrue(fix.contains("passthrough"))
    }

    func test_failsWhenXcworkspaceExistsWithAssemblyMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(
                files: ["/proj/relios.toml": SampleTOMLs.fullSample],
                directories: ["/proj/MyApp.xcworkspace"]
            )
        )

        let result = rule.evaluate(context)

        guard case .fail(_, let reason, _) = result else {
            XCTFail("Expected .fail, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("MyApp.xcworkspace"))
    }

    func test_failsWhenProjectYmlExistsWithAssemblyMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(files: [
                "/proj/relios.toml": SampleTOMLs.fullSample,
                "/proj/project.yml": "name: MyApp",
            ])
        )

        let result = rule.evaluate(context)

        guard case .fail(_, let reason, _) = result else {
            XCTFail("Expected .fail, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("project.yml"))
    }

    // MARK: - multiple markers

    func test_reportsAllMarkersWhenMultipleExistWithAssemblyMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(
                files: [
                    "/proj/relios.toml": SampleTOMLs.fullSample,
                    "/proj/project.yml": "",
                ],
                directories: ["/proj/MyApp.xcodeproj"]
            )
        )

        let result = rule.evaluate(context)

        guard case .fail(_, let reason, _) = result else {
            XCTFail("Expected .fail, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("project.yml"))
        XCTAssertTrue(reason.contains("MyApp.xcodeproj"))
    }

    // MARK: - helpers

    private func makeContext(toml: String, fs: InMemoryFileSystem) throws -> ValidationContext {
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
    }
}
