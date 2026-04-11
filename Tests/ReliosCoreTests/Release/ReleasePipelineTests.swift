import XCTest
import ReliosCore
import ReliosSupport

/// Locks pipeline acceptance gates:
///
/// c-2 gates: dry-run success (1), build failure (4), dry-run zero-write (5)
/// c-3 gates: dry-run still zero-write (c3-G5), non-dry-run DOES write (c3-G6)
final class ReleasePipelineTests: XCTestCase {

    private let appVersionSwift = """
    enum AppVersion {
        static let current = "1.2.3"
        static let build = "17"
    }
    """

    /// Builds an InMemoryFileSystem pre-seeded with everything the dry-run
    /// pipeline reads from disk: relios.toml, AppVersion.swift, and a fake
    /// binary at the spec'd build artifact path.
    private func makeReadyFileSystem() -> InMemoryFileSystem {
        InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": appVersionSwift,
            "/proj/.build/release/PortfolioManager": "fake binary blob",
        ])
    }

    private func loadSpec(from fs: InMemoryFileSystem) throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    /// Process mock that handles install-phase correctly:
    /// pgrep returns exitCode 1 ("not found"), everything else succeeds.
    private func makeInstallReadyProcess() -> MockProcessRunner {
        let process = MockProcessRunner(result: .success)
        process.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        return process
    }

    // MARK: - Gate 1 (unit half)

    func test_gate1_pipelineRunReturnsCompleteSummaryOnHappyPath() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let process = MockProcessRunner(result: .success)
        let pipeline = ReleasePipeline(fs: fs, process: process)

        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )

        XCTAssertEqual(summary.appName,         "PortfolioManager")
        XCTAssertEqual(summary.previousVersion, SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(summary.previousBuild,   BuildNumber(17))
        XCTAssertEqual(summary.nextVersion,     SemanticVersion(major: 1, minor: 2, patch: 4))
        XCTAssertEqual(summary.nextBuild,       BuildNumber(1))  // patch bump → build resets
        XCTAssertEqual(summary.buildCommand,    "swift build -c release")
        XCTAssertEqual(summary.binaryPath,      "/proj/.build/release/PortfolioManager")
        XCTAssertTrue(summary.dryRun)

        XCTAssertTrue(
            process.calls.contains(where: { $0.command == "swift build -c release" }),
            "build command must be invoked"
        )
    }

    func test_gate1_bumpNoneIncrementsBuildNumberInsteadOfVersion() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .none, dryRun: true)
        )

        XCTAssertEqual(summary.previousVersion, SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(summary.nextVersion,     SemanticVersion(major: 1, minor: 2, patch: 3))  // unchanged
        XCTAssertEqual(summary.previousBuild,   BuildNumber(17))
        XCTAssertEqual(summary.nextBuild,       BuildNumber(18))  // incremented
    }

    func test_gate1_minorAndMajorBumpsAlsoResetBuildToOne() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        let minorSummary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .minor, dryRun: true)
        )
        XCTAssertEqual(minorSummary.nextVersion, SemanticVersion(major: 1, minor: 3, patch: 0))
        XCTAssertEqual(minorSummary.nextBuild,   BuildNumber(1))

        let majorSummary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .major, dryRun: true)
        )
        XCTAssertEqual(majorSummary.nextVersion, SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(majorSummary.nextBuild,   BuildNumber(1))
    }

    // MARK: - Gate 4: build failure surfaces correctly

    func test_gate4_buildFailureSurfacesAsReleaseErrorBuildFailed() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        // `which` commands succeed (preflight), but the actual build fails
        let process = MockProcessRunner(result: .failure(exitCode: 1, stderr: "compile error"))
        process.commandOverrides["which"] = .success
        let pipeline = ReleasePipeline(fs: fs, process: process)

        XCTAssertThrowsError(try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )) { error in
            guard let e = error as? ReleaseError else {
                return XCTFail("expected ReleaseError, got \(type(of: error))")
            }
            XCTAssertEqual(e.step, .build)
            if case .buildFailed(_, _, let tail) = e {
                XCTAssertNotNil(tail)
                XCTAssertTrue(tail?.contains("compile error") ?? false)
            } else {
                XCTFail("expected .buildFailed, got \(e)")
            }
        }
    }

    func test_gate4_missingArtifactSurfacesAsReleaseErrorArtifactNotFound() throws {
        // Build "succeeds" but the binary isn't where the spec says.
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": appVersionSwift,
            // NO .build/release/PortfolioManager
        ])
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        XCTAssertThrowsError(try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )) { error in
            guard let e = error as? ReleaseError else { return XCTFail("wrong type") }
            XCTAssertEqual(e.step, .verifyBuildArtifact)
            if case .artifactNotFound(let searched) = e {
                XCTAssertFalse(searched.isEmpty)
            } else {
                XCTFail("expected .artifactNotFound, got \(e)")
            }
        }
    }

    // MARK: - Gate 5: dry-run never writes ANYWHERE

    func test_gate5_happyPathDryRunMakesZeroFilesystemWrites() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        XCTAssertEqual(fs.writeLog, [], "writeLog must start empty (sanity)")

        _ = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )

        XCTAssertEqual(
            fs.writeLog, [],
            "dry-run pipeline made unexpected writes: \(fs.writeLog)"
        )
    }

    func test_gate5_failurePathAlsoMakesZeroWrites() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(
            fs: fs,
            process: MockProcessRunner(result: .failure(exitCode: 1, stderr: "boom"))
        )

        do {
            _ = try pipeline.run(
                spec: spec,
                projectRoot: "/proj",
                options: ReleaseOptions(bump: .patch, dryRun: true)
            )
            XCTFail("expected pipeline to throw")
        } catch {
            // expected
        }

        XCTAssertEqual(
            fs.writeLog, [],
            "even on failure, dry-run must make zero writes — got \(fs.writeLog)"
        )
    }

    // MARK: - preflight failure surfaces with rule title

    func test_preflightFailureSurfacesWithRuleTitle() throws {
        // Force SpecValidityRule to fail by clearing bundle_id.
        let badToml = SampleTOMLs.fullSample.replacingOccurrences(
            of: #"bundle_id = "com.chan.portfolio-manager""#,
            with: #"bundle_id = """#
        )
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": badToml,
            "/proj/DesignMe/App/AppVersion.swift": appVersionSwift,
            "/proj/.build/release/PortfolioManager": "fake",
        ])
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        XCTAssertThrowsError(try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )) { error in
            guard let e = error as? ReleaseError else { return XCTFail("wrong type") }
            XCTAssertEqual(e.step, .preflightValidation)
            if case .preflightFailed(let title, _, _) = e {
                XCTAssertEqual(title, "bundle_id is empty")
            } else {
                XCTFail("expected .preflightFailed, got \(e)")
            }
        }
    }

    // MARK: - c-3 Gate 5 (regression): dry-run STILL zero writes after non-dry-run path landed

    func test_c3_gate5_dryRunStillMakesZeroWritesAfterNonDryPathAdded() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        _ = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .minor, dryRun: true)
        )

        XCTAssertEqual(
            fs.writeLog, [],
            "dry-run MUST remain zero-write even after non-dry-run code was added"
        )
    }

    // MARK: - c-3 Gate 6: non-dry-run path DOES write

    func test_c3_gate6_nonDryRunWritesToVersionSourceAndDist() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let process = makeInstallReadyProcess()
        let pipeline = ReleasePipeline(fs: fs, process: process)

        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: false)
        )

        // Version source was written
        XCTAssertTrue(
            fs.writeLog.contains("/proj/DesignMe/App/AppVersion.swift"),
            "non-dry-run must update version source. writeLog: \(fs.writeLog)"
        )

        // .app bundle was assembled
        XCTAssertTrue(
            fs.writeLog.contains(where: { $0.contains("dist/PortfolioManager.app/Contents/MacOS") }),
            "non-dry-run must write binary into .app bundle. writeLog: \(fs.writeLog)"
        )

        // Info.plist was generated
        XCTAssertTrue(
            fs.writeLog.contains(where: { $0.contains("Info.plist") }),
            "non-dry-run must generate Info.plist. writeLog: \(fs.writeLog)"
        )

        // codesign was called
        XCTAssertTrue(
            process.calls.contains(where: { $0.command.contains("codesign") }),
            "non-dry-run must call codesign. calls: \(process.calls)"
        )

        // Summary reflects non-dry-run
        XCTAssertFalse(summary.dryRun)
        XCTAssertNotNil(summary.bundlePath)
        XCTAssertEqual(summary.nextVersion, SemanticVersion(major: 1, minor: 2, patch: 4))
        XCTAssertEqual(summary.nextBuild,   BuildNumber(1))
    }

    func test_c3_gate6_versionSourceActuallyContainsNewValues() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: makeInstallReadyProcess())

        _ = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .minor, dryRun: false)
        )

        let updatedSource = try fs.readUTF8(at: "/proj/DesignMe/App/AppVersion.swift")
        XCTAssertTrue(updatedSource.contains(#"static let current = "1.3.0""#),
                      "version source must contain bumped version")
        XCTAssertTrue(updatedSource.contains(#"static let build = "1""#),
                      "version source must contain reset build number")
    }

    // MARK: - c-5 Gate 7: auto_open behavior

    func test_c5_gate7_nonDryRunWithAutoOpenLaunchesApp() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let process = makeInstallReadyProcess()
        let pipeline = ReleasePipeline(fs: fs, process: process)

        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: false)
        )

        // spec has auto_open = true → launched should be true
        XCTAssertTrue(summary.launched)
        XCTAssertTrue(
            process.calls.contains(where: { $0.command.contains("/usr/bin/open") }),
            "should have called open"
        )
    }

    func test_c5_gate7_noOpenFlagPreventsLaunch() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let process = makeInstallReadyProcess()
        let pipeline = ReleasePipeline(fs: fs, process: process)

        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: false, noOpen: true)
        )

        XCTAssertFalse(summary.launched)
        XCTAssertFalse(
            process.calls.contains(where: { $0.command.contains("/usr/bin/open") }),
            "should NOT have called open when noOpen=true"
        )
    }

    // MARK: - c-5 Gate 8: dry-run STILL zero writes after install code landed

    func test_c5_gate8_dryRunStillZeroWritesWithInstallCodePresent() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: MockProcessRunner(result: .success))

        _ = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )

        XCTAssertEqual(
            fs.writeLog, [],
            "dry-run MUST remain zero-write even after install code was added"
        )
    }

    // MARK: - c-3 (regression)

    func test_c3_infoPlistIsReadableAndContainsCorrectVersion() throws {
        let fs = makeReadyFileSystem()
        let spec = try loadSpec(from: fs)
        let pipeline = ReleasePipeline(fs: fs, process: makeInstallReadyProcess())

        _ = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: false)
        )

        let plistPath = "/proj/dist/PortfolioManager.app/Contents/Info.plist"
        let xml = try fs.readUTF8(at: plistPath)
        let data = xml.data(using: .utf8)!
        let dict = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as! [String: Any]

        XCTAssertEqual(dict["CFBundleShortVersionString"] as? String, "1.2.4")
        XCTAssertEqual(dict["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(dict["CFBundleIdentifier"] as? String, "com.chan.portfolio-manager")
    }
}
