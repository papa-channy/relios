import XCTest
import ReliosCore
import ReliosSupport

/// End-to-end unit test for the onboarding flow:
///   init → (files created) → doctor → (diagnostics correct) → release --dry-run
///
/// Tests both SwiftPM (assembly) and Xcode (passthrough) paths using
/// InMemoryFileSystem to avoid disk I/O.
final class InitOnboardingFlowTests: XCTestCase {

    // =========================================================================
    // MARK: - SwiftPM assembly path
    // =========================================================================

    // MARK: Gate 1: init creates both relios.toml and AppVersion.swift

    func test_gate1_initCreatesBothTomlAndAppVersion() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// manifest",
            "/proj/Sources/MyApp/MyApp.swift": "// main",
        ])

        // Simulate init: scan → skeleton → write toml + write version source
        let scanner = ProjectScanner(fs: fs)
        let scan = try scanner.scan(root: "/proj")
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        XCTAssertTrue(fs.fileExists(at: "/proj/relios.toml"),
                      "init must create relios.toml")
        XCTAssertTrue(fs.fileExists(at: "/proj/AppVersion.swift"),
                      "init must create AppVersion.swift")
    }

    // MARK: Gate 2: generated AppVersion.swift is readable by VersionSourceReader

    func test_gate2_generatedAppVersionIsReadableByPipeline() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// manifest",
            "/proj/Sources/MyApp/MyApp.swift": "// main",
        ])

        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        // Load the generated spec and use VersionSourceReader on the generated source
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let reader = VersionSourceReader(fs: fs)
        let result = try reader.read(
            spec: spec.version,
            at: "/proj/AppVersion.swift"
        )

        XCTAssertEqual(result.version, SemanticVersion(major: 0, minor: 1, patch: 0))
        XCTAssertEqual(result.build,   BuildNumber(1))
    }

    // MARK: Gate 3: init → doctor = no false-ready (both rules pass)

    func test_gate3_doctorReportsReadyAfterFreshInit() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// manifest",
            "/proj/Sources/MyApp/MyApp.swift": "// main",
        ])

        // Simulate init
        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        // Run doctor
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
        let runner = DoctorRunner(rules: [
            SpecValidityRule(),
            VersionSourceRule(),
        ])
        let diagnostics = runner.run(context)

        // Both rules must pass
        XCTAssertEqual(diagnostics.count, 2)
        for d in diagnostics {
            XCTAssertEqual(d.status, .ok,
                           "diagnostic '\(d.title)' should be .ok but was \(d.status)")
        }
    }

    // MARK: Gate 4: AppVersion.swift missing → doctor fails clearly

    func test_gate4_doctorFailsWhenAppVersionMissing() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// manifest",
            "/proj/Sources/MyApp/MyApp.swift": "// main",
        ])

        // Init but skip AppVersion.swift
        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        // deliberately NOT writing AppVersion.swift

        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
        let runner = DoctorRunner(rules: [
            SpecValidityRule(),
            VersionSourceRule(),
        ])
        let diagnostics = runner.run(context)

        // SpecValidityRule passes, VersionSourceRule fails
        let versionDiag = diagnostics.first(where: { $0.title.contains("version source") })
        XCTAssertNotNil(versionDiag, "must have a version source diagnostic")
        XCTAssertEqual(versionDiag?.status, .fail)
        XCTAssertNotNil(versionDiag?.reason)
        XCTAssertNotNil(versionDiag?.fix)
    }

    // MARK: E2E: SwiftPM init → doctor → release --dry-run

    func test_swiftpm_e2e_initThroughDryRunRelease() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// manifest",
            "/proj/Sources/MyApp/MyApp.swift": "// main",
        ])

        // 1. init
        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        XCTAssertEqual(scan.projectType, .swiftpm)
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        // 2. doctor (key rules)
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        XCTAssertEqual(spec.bundle.mode, .assembly)
        XCTAssertEqual(spec.signing.mode, .adhoc)

        let context = ValidationContext(
            spec: spec, projectRoot: "/proj", fs: fs,
            process: MockProcessRunner(result: .success)
        )
        let doctorDiags = DoctorRunner(rules: [
            XcodeProjectGuardRule(),
            SpecValidityRule(),
            VersionSourceRule(),
        ]).run(context)
        for d in doctorDiags {
            XCTAssertNotEqual(d.status, .fail,
                              "doctor rule '\(d.title)' failed: \(d.reason ?? "")")
        }

        // 3. release --dry-run (need fake binary)
        try fs.writeUTF8("fake binary", to: "/proj/.build/release/MyApp")

        // Snapshot writeLog before dry-run — init phase already wrote files.
        let writesBeforeDryRun = fs.writeLog.count

        let pipeline = ReleasePipeline(
            fs: fs,
            process: MockProcessRunner(result: .success)
        )
        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )

        XCTAssertTrue(summary.dryRun)
        XCTAssertEqual(summary.appName, "MyApp")
        XCTAssertEqual(summary.nextVersion, SemanticVersion(major: 0, minor: 1, patch: 1))
        XCTAssertEqual(fs.writeLog.count, writesBeforeDryRun,
                       "dry-run must make zero additional writes")
    }

    // =========================================================================
    // MARK: - Xcode passthrough path
    // =========================================================================

    // MARK: E2E: Xcode init → doctor → release --dry-run

    func test_xcodebuild_e2e_initThroughDryRunRelease() throws {
        let fs = InMemoryFileSystem(
            files: [:],
            directories: ["/proj/MyApp.xcodeproj"]
        )

        // 1. init
        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        XCTAssertEqual(scan.projectType, .xcodebuild)
        XCTAssertEqual(scan.binaryTarget, "MyApp")

        let skeleton = SpecSkeleton.from(scan: scan)
        XCTAssertEqual(skeleton.bundleMode, .passthrough)
        XCTAssertEqual(skeleton.signingMode, .keep)

        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        // 2. doctor
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        XCTAssertEqual(spec.project.type, .xcodebuild)
        XCTAssertEqual(spec.bundle.mode, .passthrough)
        XCTAssertEqual(spec.signing.mode, .keep)

        let context = ValidationContext(
            spec: spec, projectRoot: "/proj", fs: fs,
            process: MockProcessRunner(result: .success)
        )

        // XcodeProjectGuardRule must pass (passthrough + xcode markers = ok)
        let guardResult = XcodeProjectGuardRule().evaluate(context)
        if case .fail(_, let reason, _) = guardResult {
            XCTFail("XcodeProjectGuardRule should pass for passthrough, got: \(reason)")
        }

        let doctorDiags = DoctorRunner(rules: [
            XcodeProjectGuardRule(),
            SpecValidityRule(),
            VersionSourceRule(),
        ]).run(context)
        for d in doctorDiags {
            XCTAssertNotEqual(d.status, .fail,
                              "doctor rule '\(d.title)' failed: \(d.reason ?? "")")
        }

        // 3. release --dry-run (need fake .app at the output path)
        let appPath = "/proj/" + spec.bundle.outputPath
        try fs.createDirectory(at: appPath)

        // Snapshot writeLog before dry-run — init phase already wrote files.
        let writesBeforeDryRun = fs.writeLog.count

        let process = MockProcessRunner(result: .success)
        let pipeline = ReleasePipeline(fs: fs, process: process)
        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .patch, dryRun: true)
        )

        XCTAssertTrue(summary.dryRun)
        XCTAssertEqual(summary.appName, "MyApp")
        XCTAssertEqual(summary.nextVersion, SemanticVersion(major: 0, minor: 1, patch: 1))
        // binaryPath points to .app in passthrough mode
        XCTAssertTrue(summary.binaryPath.contains("MyApp.app"))
        XCTAssertEqual(fs.writeLog.count, writesBeforeDryRun,
                       "dry-run must make zero additional writes")
        // signing.mode = keep → no codesign invoked
        XCTAssertFalse(
            process.calls.contains(where: { $0.command.contains("codesign") }),
            "keep signing mode must not invoke codesign"
        )
    }

    // MARK: E2E: Xcode non-dry-run skips assembly + plist, writes manifest

    func test_xcodebuild_e2e_nonDryRunPassthrough() throws {
        let fs = InMemoryFileSystem(
            files: [:],
            directories: ["/proj/MyApp.xcodeproj"]
        )

        // init
        let scan = try ProjectScanner(fs: fs).scan(root: "/proj")
        let skeleton = SpecSkeleton.from(scan: scan)
        let writer = SpecSkeletonWriter(fs: fs)
        try writer.write(skeleton, to: "/proj/relios.toml")
        try writer.writeVersionSource(skeleton, to: "/proj/AppVersion.swift")

        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")

        // Seed fake .app
        let appPath = "/proj/" + spec.bundle.outputPath
        try fs.createDirectory(at: appPath)
        try fs.createDirectory(at: appPath + "/Contents")

        let process = MockProcessRunner(result: .success)
        // pgrep returns 1 (app not running)
        process.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")

        let pipeline = ReleasePipeline(fs: fs, process: process)
        let summary = try pipeline.run(
            spec: spec,
            projectRoot: "/proj",
            options: ReleaseOptions(bump: .minor, dryRun: false)
        )

        XCTAssertFalse(summary.dryRun)
        XCTAssertEqual(summary.nextVersion, SemanticVersion(major: 0, minor: 2, patch: 0))

        // Version source updated
        XCTAssertTrue(fs.writeLog.contains("/proj/AppVersion.swift"))

        // Assembly skipped
        XCTAssertFalse(fs.writeLog.contains(where: { $0.contains("Contents/MacOS") }),
                       "passthrough must NOT write binary into .app")

        // Info.plist skipped
        XCTAssertFalse(fs.writeLog.contains(where: { $0.contains("Info.plist") }),
                       "passthrough must NOT generate Info.plist")

        // No codesign (keep mode)
        XCTAssertFalse(process.calls.contains(where: { $0.command.contains("codesign") }))

        // Manifest written with correct bundle_mode
        let manifestPath = "/proj/dist/releases/latest.json"
        XCTAssertTrue(fs.fileExists(at: manifestPath))
        let manifestJson = try fs.readUTF8(at: manifestPath)
        XCTAssertTrue(manifestJson.contains("\"passthrough\""),
                      "manifest must record bundle_mode as passthrough")
    }
}
