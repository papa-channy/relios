import XCTest
import ReliosCore
import ReliosSupport

/// Focused unit tests for `SwiftBuildRunner`. Pipeline-level orchestration
/// is in `ReleasePipelineTests`; these isolate the build runner itself.
final class SwiftBuildRunnerTests: XCTestCase {

    private func loadFullSpec() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": SampleTOMLs.fullSample])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    // MARK: - runBuild

    func test_runBuildInvokesShellWithSpecCommandAndProjectRoot() throws {
        let spec = try loadFullSpec()
        let process = MockProcessRunner(result: .success)
        let runner = SwiftBuildRunner(process: process, fs: InMemoryFileSystem())

        try runner.runBuild(spec: spec, projectRoot: "/proj")

        XCTAssertEqual(process.calls.count, 1)
        XCTAssertEqual(process.calls[0].command, "swift build -c release")
        XCTAssertEqual(process.calls[0].cwd,     "/proj")
    }

    func test_runBuildThrowsNonZeroExitWhenProcessExitsNonZero() throws {
        let spec = try loadFullSpec()
        let process = MockProcessRunner(result: .failure(exitCode: 1, stderr: "tons of swift errors"))
        let runner = SwiftBuildRunner(process: process, fs: InMemoryFileSystem())

        XCTAssertThrowsError(try runner.runBuild(spec: spec, projectRoot: "/proj")) { error in
            guard let e = error as? BuildError else { return XCTFail("wrong type") }
            if case .nonZeroExit(_, let code, let tail) = e {
                XCTAssertEqual(code, 1)
                XCTAssertTrue(tail.contains("swift errors"))
            } else {
                XCTFail("expected .nonZeroExit, got \(e)")
            }
        }
    }

    // MARK: - locateBinary

    func test_locateBinaryReturnsPrimaryWhenItExists() throws {
        let spec = try loadFullSpec()
        let fs = InMemoryFileSystem(files: [
            "/proj/.build/release/PortfolioManager": "fake binary"
        ])
        let runner = SwiftBuildRunner(process: MockProcessRunner(result: .success), fs: fs)

        let path = try runner.locateBinary(spec: spec, projectRoot: "/proj")

        XCTAssertEqual(path, "/proj/.build/release/PortfolioManager")
    }

    func test_locateBinaryFallsBackToTripleSubdirWhenPrimaryMissing() throws {
        let spec = try loadFullSpec()
        let fs = InMemoryFileSystem(files: [
            "/proj/.build/arm64-apple-macosx/release/PortfolioManager": "fake binary"
        ])
        let runner = SwiftBuildRunner(process: MockProcessRunner(result: .success), fs: fs)

        let path = try runner.locateBinary(spec: spec, projectRoot: "/proj")

        XCTAssertEqual(path, "/proj/.build/arm64-apple-macosx/release/PortfolioManager")
    }

    func test_locateBinaryThrowsBinaryNotFoundWithSearchedPaths() throws {
        let spec = try loadFullSpec()
        let runner = SwiftBuildRunner(process: MockProcessRunner(result: .success), fs: InMemoryFileSystem())

        XCTAssertThrowsError(try runner.locateBinary(spec: spec, projectRoot: "/proj")) { error in
            guard let e = error as? BuildError else { return XCTFail("wrong type") }
            if case .binaryNotFound(let searched) = e {
                XCTAssertGreaterThanOrEqual(searched.count, 2)
                XCTAssertTrue(searched.contains("/proj/.build/release/PortfolioManager"))
            } else {
                XCTFail("expected .binaryNotFound, got \(e)")
            }
        }
    }
}
