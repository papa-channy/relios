import XCTest
import ReliosCore
import ReliosSupport

/// Locks the (c-2) Gate 2: VersionSourceReader extracts current version + build
/// from a Swift source file using the regex patterns from `[version]`.
final class VersionSourceReaderTests: XCTestCase {

    private let versionSpec = VersionSection_forTesting(
        sourceFile: "AppVersion.swift",
        versionPattern: #"static let current = "(.*)""#,
        buildPattern:   #"static let build = "(.*)""#
    )

    private let sampleSource = """
    enum AppVersion {
        static let current = "1.2.3"
        static let build = "17"
    }
    """

    // MARK: - Gate 2: happy path

    func test_gate2_readsVersionAndBuildFromCanonicalSource() throws {
        let fs = InMemoryFileSystem(files: ["/proj/AppVersion.swift": sampleSource])
        let reader = VersionSourceReader(fs: fs)

        let result = try reader.read(spec: versionSpec, at: "/proj/AppVersion.swift")

        XCTAssertEqual(result.version, SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(result.build,   BuildNumber(17))
    }

    // MARK: - error paths

    func test_throwsUnreadableWhenFileMissing() {
        let reader = VersionSourceReader(fs: InMemoryFileSystem(files: [:]))

        XCTAssertThrowsError(try reader.read(spec: versionSpec, at: "/proj/AppVersion.swift")) { error in
            guard let e = error as? VersionSourceError else { return XCTFail("wrong type") }
            if case .unreadable = e { /* ok */ } else { XCTFail("expected .unreadable, got \(e)") }
        }
    }

    func test_throwsVersionPatternUnmatchedWhenSourceLacksVersionLine() {
        let fs = InMemoryFileSystem(files: [
            "/proj/AppVersion.swift": "// no version here\nstatic let build = \"17\"\n"
        ])
        let reader = VersionSourceReader(fs: fs)

        XCTAssertThrowsError(try reader.read(spec: versionSpec, at: "/proj/AppVersion.swift")) { error in
            guard let e = error as? VersionSourceError else { return XCTFail("wrong type") }
            if case .versionPatternUnmatched = e { /* ok */ } else { XCTFail("expected .versionPatternUnmatched, got \(e)") }
        }
    }

    func test_throwsBuildPatternUnmatchedWhenSourceLacksBuildLine() {
        let fs = InMemoryFileSystem(files: [
            "/proj/AppVersion.swift": "static let current = \"1.2.3\"\n// no build line\n"
        ])
        let reader = VersionSourceReader(fs: fs)

        XCTAssertThrowsError(try reader.read(spec: versionSpec, at: "/proj/AppVersion.swift")) { error in
            guard let e = error as? VersionSourceError else { return XCTFail("wrong type") }
            if case .buildPatternUnmatched = e { /* ok */ } else { XCTFail("expected .buildPatternUnmatched, got \(e)") }
        }
    }

    func test_throwsUnparseableSemverWhenCapturedStringIsNotAVersion() {
        let fs = InMemoryFileSystem(files: [
            "/proj/AppVersion.swift": "static let current = \"abc\"\nstatic let build = \"17\"\n"
        ])
        let reader = VersionSourceReader(fs: fs)

        XCTAssertThrowsError(try reader.read(spec: versionSpec, at: "/proj/AppVersion.swift")) { error in
            guard let e = error as? VersionSourceError else { return XCTFail("wrong type") }
            if case .unparseableSemver = e { /* ok */ } else { XCTFail("expected .unparseableSemver, got \(e)") }
        }
    }
}

// MARK: - test helper

/// VersionSection has no public memberwise init (it's Decodable-only), so
/// we decode a tiny TOML snippet to construct one for the tests.
private func VersionSection_forTesting(
    sourceFile: String,
    versionPattern: String,
    buildPattern: String
) -> VersionSection {
    let toml = """
    [app]
    name = "X"
    display_name = "X"
    bundle_id = "com.x"
    min_macos = "14.0"
    category = "x"

    [project]
    type = "swiftpm"
    root = "."
    binary_target = "X"

    [version]
    source_file = "\(sourceFile)"
    version_pattern = '\(versionPattern)'
    build_pattern = '\(buildPattern)'

    [build]
    command = "swift build -c release"
    binary_path = ".build/release/X"

    [assets]

    [bundle]
    output_path = "dist/X.app"
    plist_mode = "generate"

    [install]
    path = "/Applications/X.app"
    auto_open = true
    backup_dir = "dist/app-backups"
    keep_backups = 3
    quit_running_app = true

    [signing]
    mode = "adhoc"
    """
    let fs = InMemoryFileSystem(files: ["/x/relios.toml": toml])
    let spec = try! SpecLoader(fs: fs).load(from: "/x/relios.toml")
    return spec.version
}
