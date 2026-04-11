import XCTest
import ReliosCore
import ReliosSupport

/// Locks the (c-1) Init slice's writer contract:
///   - rendered TOML must roundtrip cleanly through `SpecLoader`
///   - all 5 minimum-required fields (per the slice gates) are populated
///   - `write(_:to:)` actually writes the file at the given path
final class SpecSkeletonWriterTests: XCTestCase {

    // MARK: - Gate 2 + Gate 3 (init slice): TOML is parseable + minimum fields filled

    func test_renderedSpecRoundtripsCleanlyThroughSpecLoader() throws {
        let skeleton = SpecSkeleton.from(scan: ProjectScanResult(
            root: "/proj",
            projectType: .swiftpm,
            binaryTarget: "PortfolioManager"
        ))

        let writer = SpecSkeletonWriter(fs: InMemoryFileSystem())
        let toml = writer.render(skeleton)

        // Roundtrip through the same SpecLoader real init uses.
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")

        // The 5 minimum fields the user listed in the (c-1) gates:
        XCTAssertEqual(spec.project.type,         .swiftpm,                   "[project].type filled")
        XCTAssertEqual(spec.project.binaryTarget, "PortfolioManager",         "[project].binary_target filled")
        XCTAssertEqual(spec.app.name,             "PortfolioManager",         "[app].name filled")
        XCTAssertEqual(spec.build.command,        "swift build -c release",   "[build].command filled")
        XCTAssertEqual(spec.bundle.outputPath,    "dist/PortfolioManager.app","[bundle].output_path filled")
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

    // MARK: - Gate 1 (init slice): file actually written

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
}
