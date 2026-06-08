import XCTest
import ReliosCore
import ReliosSupport

/// `relios build` engine: build + verify only — no bump, no install, no writes.
final class BuildOnlyRunnerTests: XCTestCase {

    private func loadSpec(_ fs: InMemoryFileSystem, path: String = "/proj/relios.toml") throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: path)
    }

    // Assembly happy path: builds, locates the binary, makes ZERO writes.
    func test_assembly_buildsAndLocatesBinary_noWrites() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/.build/release/PortfolioManager": "binary",
        ])
        let spec = try loadSpec(fs)
        let process = MockProcessRunner(result: .success)

        let result = try BuildOnlyRunner(process: process, fs: fs).run(spec: spec, projectRoot: "/proj")

        XCTAssertFalse(result.passthrough)
        XCTAssertEqual(result.artifactPath, "/proj/.build/release/PortfolioManager")
        XCTAssertEqual(result.buildCommand, "swift build -c release")
        // The build command was invoked.
        XCTAssertTrue(process.calls.contains { $0.command == "swift build -c release" })
        // build never mutates Relios-owned state.
        XCTAssertEqual(fs.writeLog, [], "build must not write (no bump, no install): \(fs.writeLog)")
    }

    // Build command fails → BuildError.nonZeroExit (with stderr tail).
    func test_buildFailureSurfacesNonZeroExit() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/.build/release/PortfolioManager": "binary",
        ])
        let spec = try loadSpec(fs)
        let process = MockProcessRunner(result: .failure(exitCode: 65, stderr: "compile error"))

        XCTAssertThrowsError(try BuildOnlyRunner(process: process, fs: fs).run(spec: spec, projectRoot: "/proj")) { error in
            guard let e = error as? BuildError else { return XCTFail("wrong type: \(error)") }
            if case .nonZeroExit(_, let code, let tail) = e {
                XCTAssertEqual(code, 65)
                XCTAssertTrue(tail.contains("compile error"))
            } else {
                XCTFail("expected .nonZeroExit, got \(e)")
            }
        }
    }

    // Build "succeeds" but the binary is missing → binaryNotFound, Fix lists paths.
    func test_artifactMissingSurfacesBinaryNotFound() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            // no .build/release/PortfolioManager
        ])
        let spec = try loadSpec(fs)
        let process = MockProcessRunner(result: .success)

        XCTAssertThrowsError(try BuildOnlyRunner(process: process, fs: fs).run(spec: spec, projectRoot: "/proj")) { error in
            guard let e = error as? BuildError else { return XCTFail("wrong type: \(error)") }
            if case .binaryNotFound(let searched) = e {
                XCTAssertFalse(searched.isEmpty)
                XCTAssertTrue(e.shortFix.contains("Searched:"))
            } else {
                XCTFail("expected .binaryNotFound, got \(e)")
            }
        }
    }

    // Passthrough happy path: verifies the .app, no writes.
    func test_passthrough_verifiesApp_noWrites() throws {
        let fs = InMemoryFileSystem(
            files: ["/proj/relios.toml": SampleTOMLs.xcodebuildPassthrough],
            directories: ["/proj/build/Build/Products/Release/MyXcodeApp.app"]
        )
        let spec = try loadSpec(fs)
        let process = MockProcessRunner(result: .success)

        let result = try BuildOnlyRunner(process: process, fs: fs).run(spec: spec, projectRoot: "/proj")

        XCTAssertTrue(result.passthrough)
        XCTAssertEqual(result.artifactPath, "/proj/build/Build/Products/Release/MyXcodeApp.app")
        XCTAssertEqual(fs.writeLog, [])
    }

    // Passthrough but xcodebuild produced no .app → binaryNotFound.
    func test_passthrough_missingAppSurfacesBinaryNotFound() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.xcodebuildPassthrough,
            // no .app directory
        ])
        let spec = try loadSpec(fs)
        let process = MockProcessRunner(result: .success)

        XCTAssertThrowsError(try BuildOnlyRunner(process: process, fs: fs).run(spec: spec, projectRoot: "/proj")) { error in
            guard let e = error as? BuildError else { return XCTFail("wrong type: \(error)") }
            if case .binaryNotFound = e { /* ok */ } else {
                XCTFail("expected .binaryNotFound, got \(e)")
            }
        }
    }
}
