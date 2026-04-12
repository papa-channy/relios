import XCTest
import ReliosCore
import ReliosSupport

/// Locks the (a)-slice acceptance gates as code:
///
/// 1. relios.toml fixture로 decode 성공
/// 2. 모든 section 값 정확히 매핑
/// 3. 빈 문자열 → nil 정규화 정상 동작
/// 4. 잘못된 TOML → SpecLoadError로 fail
/// 5. SpecLoader가 FileSystem mock으로 테스트 가능
final class SpecDecodingTests: XCTestCase {

    // MARK: - Gate 1

    func test_gate1_decodesFullSampleSuccessfully() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.app.name, "PortfolioManager")  // 단순 sanity
    }

    // MARK: - Gate 2

    func test_gate2_app_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.app.name,        "PortfolioManager")
        XCTAssertEqual(spec.app.displayName, "Portfolio Manager")
        XCTAssertEqual(spec.app.bundleId,    "com.chan.portfolio-manager")
        XCTAssertEqual(spec.app.minMacOS,    "14.0")
        XCTAssertEqual(spec.app.category,    "public.app-category.developer-tools")
    }

    func test_gate2_project_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.project.type,         .swiftpm)
        XCTAssertEqual(spec.project.root,         ".")
        XCTAssertEqual(spec.project.binaryTarget, "PortfolioManager")
    }

    func test_gate2_version_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.version.sourceFile,     "DesignMe/App/AppVersion.swift")
        XCTAssertEqual(spec.version.versionPattern, #"static let current = "(.*)""#)
        XCTAssertEqual(spec.version.buildPattern,   #"static let build = "(.*)""#)
    }

    func test_gate2_build_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.build.command,            "swift build -c release")
        XCTAssertEqual(spec.build.binaryPath,         ".build/release/PortfolioManager")
        XCTAssertEqual(spec.build.resourceBundlePath, ".build/release/PortfolioManager_PortfolioManager.bundle")
    }

    func test_gate2_assets_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.assets.iconPath, "DesignMe/Resources/AppIcon.icns")
    }

    func test_gate2_bundle_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.bundle.outputPath, "dist/PortfolioManager.app")
        XCTAssertEqual(spec.bundle.plistMode,  .generate)
        XCTAssertEqual(spec.bundle.mode,       .assembly)
    }

    func test_gate2_install_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.install.path,           "/Applications/PortfolioManager.app")
        XCTAssertEqual(spec.install.autoOpen,       true)
        XCTAssertEqual(spec.install.backupDir,      "dist/app-backups")
        XCTAssertEqual(spec.install.keepBackups,    3)
        XCTAssertEqual(spec.install.quitRunningApp, true)
    }

    func test_gate2_signing_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.signing.mode, .adhoc)
    }

    // MARK: - xcodebuild + passthrough

    func test_decodesXcodebuildPassthroughSample() throws {
        let spec = try loadXcodebuildPassthrough()
        XCTAssertEqual(spec.project.type, .xcodebuild)
        XCTAssertEqual(spec.bundle.mode,  .passthrough)
        XCTAssertEqual(spec.app.name,     "MyXcodeApp")
        XCTAssertTrue(spec.build.command.contains("xcodebuild"))
    }

    func test_bundleModeDefaultsToAssemblyWhenOmitted() throws {
        let spec = try loadMinimalWithEmptyOptionals()
        XCTAssertEqual(spec.bundle.mode, .assembly,
                       "mode must default to .assembly for backward compat")
    }

    // MARK: - Gate 3

    func test_gate3_emptyResourceBundlePath_normalizesToNil() throws {
        let spec = try loadMinimalWithEmptyOptionals()
        XCTAssertNil(spec.build.resourceBundlePath,
                     "empty resource_bundle_path must normalize to nil")
    }

    func test_gate3_emptyIconPath_normalizesToNil() throws {
        let spec = try loadMinimalWithEmptyOptionals()
        XCTAssertNil(spec.assets.iconPath,
                     "empty icon_path must normalize to nil")
    }

    // MARK: - Gate 4

    func test_gate4_malformedToml_throwsSpecLoadErrorMalformed() {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": "not [valid = toml { ="
        ])
        let loader = SpecLoader(fs: fs)

        XCTAssertThrowsError(try loader.load(from: "/proj/relios.toml")) { error in
            guard let specError = error as? SpecLoadError else {
                XCTFail("Expected SpecLoadError, got \(type(of: error))")
                return
            }
            if case .malformed = specError { /* ok */ } else {
                XCTFail("Expected .malformed, got \(specError)")
            }
        }
    }

    func test_gate4_missingFile_throwsSpecLoadErrorMissing() {
        let loader = SpecLoader(fs: InMemoryFileSystem(files: [:]))

        XCTAssertThrowsError(try loader.load(from: "/proj/relios.toml")) { error in
            guard let specError = error as? SpecLoadError else {
                XCTFail("Expected SpecLoadError, got \(type(of: error))")
                return
            }
            if case .missing(let path) = specError {
                XCTAssertEqual(path, "/proj/relios.toml")
            } else {
                XCTFail("Expected .missing, got \(specError)")
            }
        }
    }

    // MARK: - Gate 5

    /// Proves the loader never touches disk: a path that no real filesystem
    /// could plausibly resolve still loads cleanly through the injected mock.
    func test_gate5_specLoaderResolvesEntirelyThroughInjectedFileSystem() throws {
        let impossiblePath = "/__definitely_not_on_disk__/relios.toml"
        let fs = InMemoryFileSystem(files: [
            impossiblePath: SampleTOMLs.fullSample
        ])
        let spec = try SpecLoader(fs: fs).load(from: impossiblePath)
        XCTAssertEqual(spec.app.name, "PortfolioManager")
    }

    // MARK: - helpers

    private func loadFullSample() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample
        ])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    private func loadMinimalWithEmptyOptionals() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.minimalWithEmptyOptionals
        ])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    private func loadXcodebuildPassthrough() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.xcodebuildPassthrough
        ])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }
}
