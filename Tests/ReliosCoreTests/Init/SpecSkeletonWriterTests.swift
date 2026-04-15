import XCTest
import ReliosCore
import ReliosSupport

/// Locks the Init slice's writer contract:
///   - rendered TOML must roundtrip cleanly through `SpecLoader`
///   - all minimum-required fields are populated
///   - `write(_:to:)` actually writes the file at the given path
///   - xcodebuild skeleton roundtrips with passthrough mode
final class SpecSkeletonWriterTests: XCTestCase {

    // MARK: - SwiftPM skeleton

    func test_renderedSpecRoundtripsCleanlyThroughSpecLoader() throws {
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "PortfolioManager"
        ))

        let writer = SpecSkeletonWriter(fs: InMemoryFileSystem())
        let toml = writer.render(skeleton)

        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")

        XCTAssertEqual(spec.project.type,         .swiftpm)
        XCTAssertEqual(spec.project.binaryTarget, "PortfolioManager")
        XCTAssertEqual(spec.app.name,             "PortfolioManager")
        XCTAssertEqual(spec.build.command,        "swift build -c release")
        XCTAssertEqual(spec.bundle.outputPath,    "dist/PortfolioManager.app")
        XCTAssertEqual(spec.bundle.mode,          .assembly)
    }

    func test_renderedSpecPassesSpecValidityRule() throws {
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "PortfolioManager"
        ))
        let toml = SpecSkeletonWriter(fs: InMemoryFileSystem()).render(skeleton)
        let loaderFS = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: loaderFS).load(from: "/proj/relios.toml")

        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: loaderFS)
        let result = SpecValidityRule().evaluate(context)

        if case .ok = result { /* expected */ } else {
            XCTFail("freshly init'd spec must pass SpecValidityRule, got \(result)")
        }
    }

    func test_writeActuallyPersistsFileToInjectedFileSystem() throws {
        let fs = InMemoryFileSystem()
        let writer = SpecSkeletonWriter(fs: fs)
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "X"
        ))

        try writer.write(skeleton, to: "/proj/relios.toml")

        XCTAssertTrue(fs.fileExists(at: "/proj/relios.toml"))
        let content = try fs.readUTF8(at: "/proj/relios.toml")
        XCTAssertTrue(content.contains("[app]"))
        XCTAssertTrue(content.contains("name = \"X\""))
    }

    // MARK: - Xcodebuild skeleton

    func test_xcodebuildSkeletonRoundtripsWithPassthroughMode() throws {
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .xcodebuild,
            binaryTarget: "MyApp"
        ))

        let writer = SpecSkeletonWriter(fs: InMemoryFileSystem())
        let toml = writer.render(skeleton)

        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")

        XCTAssertEqual(spec.project.type,  .xcodebuild)
        XCTAssertEqual(spec.bundle.mode,   .passthrough)
        XCTAssertEqual(spec.app.name,      "MyApp")
        XCTAssertTrue(spec.build.command.contains("xcodebuild"))
        XCTAssertTrue(spec.bundle.outputPath.contains("MyApp.app"))
    }

    // MARK: - Developer ID auto-population

    func test_withDeveloperID_populatesIdentityAndTeamInRenderedTOML() throws {
        let base = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "App"
        ))
        let skeleton = base.withDeveloperID(
            identity: "Developer ID Application: Chan (ABCDE12345)",
            teamID: "ABCDE12345"
        )

        let toml = SpecSkeletonWriter(fs: InMemoryFileSystem()).render(skeleton)
        XCTAssertTrue(toml.contains("mode = \"developer-id\""))
        XCTAssertTrue(toml.contains("identity = \"Developer ID Application: Chan (ABCDE12345)\""))
        XCTAssertTrue(toml.contains("team_id = \"ABCDE12345\""))

        // Roundtrip: the rendered TOML must still be loadable.
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        XCTAssertEqual(spec.signing.mode, .developerID)
        XCTAssertEqual(spec.signing.identity, "Developer ID Application: Chan (ABCDE12345)")
        XCTAssertEqual(spec.signing.teamID, "ABCDE12345")
    }

    func test_defaultSkeleton_leavesSigningIdentityEmpty() {
        let base = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "App"
        ))
        let toml = SpecSkeletonWriter(fs: InMemoryFileSystem()).render(base)
        XCTAssertTrue(toml.contains("mode = \"adhoc\""))
        XCTAssertTrue(toml.contains("identity = \"\""))
        XCTAssertTrue(toml.contains("team_id = \"\""))
    }

    func test_xcodebuildSkeletonPassesSpecValidityRule() throws {
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .xcodebuild,
            binaryTarget: "MyApp"
        ))
        let toml = SpecSkeletonWriter(fs: InMemoryFileSystem()).render(skeleton)
        let loaderFS = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: loaderFS).load(from: "/proj/relios.toml")

        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: loaderFS)
        let result = SpecValidityRule().evaluate(context)

        if case .ok = result { /* expected */ } else {
            XCTFail("xcodebuild spec must pass SpecValidityRule, got \(result)")
        }
    }
}
