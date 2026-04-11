import XCTest
import ReliosCore
import ReliosSupport

/// End-to-end unit test for the onboarding flow:
///   init → (files created) → doctor → (diagnostics correct)
///
/// This test replays the exact sequence a first-time user would do,
/// using InMemoryFileSystem to avoid disk I/O.
final class InitOnboardingFlowTests: XCTestCase {

    // MARK: - Gate 1: init creates both relios.toml and AppVersion.swift

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

    // MARK: - Gate 2: generated AppVersion.swift is readable by VersionSourceReader

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

    // MARK: - Gate 3: init → doctor = no false-ready (both rules pass)

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

    // MARK: - Gate 4: AppVersion.swift missing → doctor fails clearly

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
}
