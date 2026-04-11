import XCTest
import ReliosCore
import ReliosSupport

/// Gate 2: .app bundle layout has Contents/MacOS/<binary>.
final class AppBundleAssemblerTests: XCTestCase {

    func test_gate2_createsCorrectBundleLayout() throws {
        let spec = try loadFullSpec()
        let fs = InMemoryFileSystem(files: [
            "/proj/.build/release/PortfolioManager": "binary-bytes"
        ])
        let assembler = AppBundleAssembler(fs: fs)

        _ = try assembler.assemble(
            spec: spec,
            binarySourcePath: "/proj/.build/release/PortfolioManager",
            outputPath: "/proj/dist/PortfolioManager.app",
            projectRoot: "/proj"
        )

        // Contents/MacOS/<binary> must exist
        XCTAssertTrue(
            fs.fileExists(at: "/proj/dist/PortfolioManager.app/Contents/MacOS/PortfolioManager"),
            "binary must be at Contents/MacOS/<name>"
        )
        // Binary content preserved
        let content = try fs.readUTF8(at: "/proj/dist/PortfolioManager.app/Contents/MacOS/PortfolioManager")
        XCTAssertEqual(content, "binary-bytes")
    }

    func test_copiesIconWhenPresent() throws {
        let spec = try loadFullSpec()
        let fs = InMemoryFileSystem(files: [
            "/proj/.build/release/PortfolioManager": "binary",
            "/proj/DesignMe/Resources/AppIcon.icns": "icon-data",
        ])
        let assembler = AppBundleAssembler(fs: fs)

        _ = try assembler.assemble(
            spec: spec,
            binarySourcePath: "/proj/.build/release/PortfolioManager",
            outputPath: "/proj/dist/PortfolioManager.app",
            projectRoot: "/proj"
        )

        // Icon should be in Resources
        let iconPath = "/proj/dist/PortfolioManager.app/Contents/Resources/AppIcon.icns"
        XCTAssertTrue(fs.fileExists(at: iconPath))
        XCTAssertEqual(try fs.readUTF8(at: iconPath), "icon-data")
    }

    private func loadFullSpec() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: ["/x/relios.toml": SampleTOMLs.fullSample])
        return try SpecLoader(fs: fs).load(from: "/x/relios.toml")
    }
}
