import XCTest
import Foundation
import ReliosCore
import ReliosSupport

/// Gate 3: Info.plist contains correct values from spec.
final class InfoPlistWriterTests: XCTestCase {

    func test_gate3_generatedPlistContainsCorrectValues() throws {
        let spec = try loadFullSpec()
        let fs = InMemoryFileSystem()
        let writer = InfoPlistWriter(fs: fs, mode: .generate)

        try writer.write(
            spec: spec,
            version: SemanticVersion(major: 1, minor: 2, patch: 4),
            build: BuildNumber(1),
            toContentsDir: "/app/Contents"
        )

        let plistPath = "/app/Contents/Info.plist"
        XCTAssertTrue(fs.fileExists(at: plistPath))

        let xml = try fs.readUTF8(at: plistPath)
        let data = xml.data(using: .utf8)!
        let dict = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]

        XCTAssertEqual(dict["CFBundleExecutable"]        as? String, "PortfolioManager")
        XCTAssertEqual(dict["CFBundleIdentifier"]        as? String, "com.chan.portfolio-manager")
        XCTAssertEqual(dict["CFBundleName"]              as? String, "Portfolio Manager")
        XCTAssertEqual(dict["CFBundleDisplayName"]       as? String, "Portfolio Manager")
        XCTAssertEqual(dict["CFBundleShortVersionString"] as? String, "1.2.4")
        XCTAssertEqual(dict["CFBundleVersion"]           as? String, "1")
        XCTAssertEqual(dict["CFBundlePackageType"]       as? String, "APPL")
        XCTAssertEqual(dict["LSMinimumSystemVersion"]    as? String, "14.0")
        XCTAssertEqual(dict["LSApplicationCategoryType"] as? String, "public.app-category.developer-tools")
    }

    private func loadFullSpec() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: ["/x/relios.toml": SampleTOMLs.fullSample])
        return try SpecLoader(fs: fs).load(from: "/x/relios.toml")
    }
}
