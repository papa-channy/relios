import XCTest
import ReliosCore
import ReliosSupport

/// Gate 1: VersionSourceUpdater rewrites version + build correctly.
final class VersionSourceUpdaterTests: XCTestCase {

    private let versionPattern = #"static let current = "(.*)""#
    private let buildPattern   = #"static let build = "(.*)""#

    func test_gate1_updatesVersionAndBuildInPlace() throws {
        let original = """
        enum AppVersion {
            static let current = "1.2.3"
            static let build = "17"
        }
        """
        let fs = InMemoryFileSystem(files: ["/proj/AV.swift": original])
        let updater = VersionSourceUpdater(fs: fs)

        try updater.update(
            at: "/proj/AV.swift",
            versionPattern: versionPattern,
            newVersion: SemanticVersion(major: 1, minor: 2, patch: 4),
            buildPattern: buildPattern,
            newBuild: BuildNumber(1)
        )

        let updated = try fs.readUTF8(at: "/proj/AV.swift")
        XCTAssertTrue(updated.contains(#"static let current = "1.2.4""#))
        XCTAssertTrue(updated.contains(#"static let build = "1""#))
        // Surrounding code untouched
        XCTAssertTrue(updated.contains("enum AppVersion"))
    }

    func test_gate1_roundtripsWithVersionSourceReader() throws {
        let original = """
        struct V {
            static let current = "2.0.0"
            static let build = "42"
        }
        """
        let fs = InMemoryFileSystem(files: ["/proj/V.swift": original])
        let updater = VersionSourceUpdater(fs: fs)

        try updater.update(
            at: "/proj/V.swift",
            versionPattern: versionPattern,
            newVersion: SemanticVersion(major: 3, minor: 0, patch: 0),
            buildPattern: buildPattern,
            newBuild: BuildNumber(1)
        )

        // Now re-read with VersionSourceReader
        let toml = SampleTOMLs.fullSample
            .replacingOccurrences(of: "DesignMe/App/AppVersion.swift", with: "V.swift")
        let specFS = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        let spec = try SpecLoader(fs: specFS).load(from: "/proj/relios.toml")
        let reader = VersionSourceReader(fs: fs)
        let result = try reader.read(spec: spec.version, at: "/proj/V.swift")

        XCTAssertEqual(result.version, SemanticVersion(major: 3, minor: 0, patch: 0))
        XCTAssertEqual(result.build,   BuildNumber(1))
    }

    func test_throwsWhenVersionPatternDoesNotMatch() {
        let fs = InMemoryFileSystem(files: ["/proj/V.swift": "no version here"])
        let updater = VersionSourceUpdater(fs: fs)

        XCTAssertThrowsError(try updater.update(
            at: "/proj/V.swift",
            versionPattern: versionPattern,
            newVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            buildPattern: buildPattern,
            newBuild: BuildNumber(1)
        )) { error in
            guard let e = error as? VersionSourceError else { return XCTFail("wrong type") }
            if case .versionPatternUnmatched = e { /* ok */ } else { XCTFail("got \(e)") }
        }
    }

    func test_doesNotWriteWhenPatternFails() {
        let fs = InMemoryFileSystem(files: ["/proj/V.swift": "no patterns"])
        let updater = VersionSourceUpdater(fs: fs)

        _ = try? updater.update(
            at: "/proj/V.swift",
            versionPattern: versionPattern,
            newVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            buildPattern: buildPattern,
            newBuild: BuildNumber(1)
        )

        // File must still be original content — no partial write
        XCTAssertEqual(try fs.readUTF8(at: "/proj/V.swift"), "no patterns")
        XCTAssertEqual(fs.writeLog, [], "updater must not write on failure")
    }
}
