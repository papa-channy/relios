import XCTest
import ReliosCore
import ReliosSupport

/// Locks the `ci init` contract:
///   - passthrough spec → release.yml contains xcodebuild + output_path
///   - assembly spec    → release.yml installs relios + invokes `relios release`
///   - both modes also emit ci.yml
///   - missing spec is surfaced as CIError.specMissing
///   - existing workflow is refused without --force, overwritten with
///   - error lists all conflicting files together
final class CIInitRunnerTests: XCTestCase {

    private func assemblyTOML(appName: String = "PortfolioManager") -> String {
        return """
        [app]
        name = "\(appName)"
        display_name = "\(appName)"
        bundle_id = "com.example.\(appName.lowercased())"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"

        [project]
        type = "swiftpm"
        root = "."
        binary_target = "\(appName)"

        [version]
        source_file = "AppVersion.swift"
        version_pattern = 'static let current = "(.*)"'
        build_pattern = 'static let build = "(.*)"'

        [build]
        command = "swift build -c release"
        binary_path = ".build/release/\(appName)"
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "dist/\(appName).app"
        plist_mode = "generate"
        mode = "assembly"

        [install]
        path = "/Applications/\(appName).app"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "adhoc"
        """
    }

    private func passthroughTOML(appName: String = "MyApp") -> String {
        return """
        [app]
        name = "\(appName)"
        display_name = "\(appName)"
        bundle_id = "com.example.\(appName.lowercased())"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"

        [project]
        type = "xcodebuild"
        root = "."
        binary_target = "\(appName)"

        [version]
        source_file = "AppVersion.swift"
        version_pattern = 'static let current = "(.*)"'
        build_pattern = 'static let build = "(.*)"'

        [build]
        command = "xcodebuild -scheme \(appName) -configuration Release -derivedDataPath build build"
        binary_path = ""
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "build/Build/Products/Release/\(appName).app"
        plist_mode = "generate"
        mode = "passthrough"

        [install]
        path = "/Applications/\(appName).app"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "keep"
        """
    }

    // MARK: - release.yml generation

    func test_passthrough_specProducesXcodebuildReleaseWorkflow() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": passthroughTOML()])
        let runner = CIInitRunner(fs: fs)

        let result = try runner.run(projectRoot: "/proj", force: false)

        XCTAssertEqual(result.mode, .passthrough)
        XCTAssertEqual(result.projectType, .xcodebuild)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertEqual(result.files.map(\.path), [
            "/proj/.github/workflows/release.yml",
            "/proj/.github/workflows/ci.yml",
        ])
        XCTAssertTrue(result.files.allSatisfy { !$0.overwritten })

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertTrue(yaml.contains("xcodebuild -scheme MyApp"))
        XCTAssertTrue(yaml.contains("build/Build/Products/Release/MyApp.app"))
        XCTAssertTrue(yaml.contains("MyApp-${TAG}.zip"))
        XCTAssertTrue(yaml.contains("softprops/action-gh-release@"))
        XCTAssertFalse(yaml.contains("brew install papa-channy/relios/relios"))
    }

    func test_assembly_specInvokesReliosReleaseInCI() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        let runner = CIInitRunner(fs: fs)

        let result = try runner.run(projectRoot: "/proj", force: false)

        XCTAssertEqual(result.mode, .assembly)
        XCTAssertEqual(result.projectType, .swiftpm)

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertTrue(yaml.contains("brew install papa-channy/relios/relios"))
        XCTAssertTrue(yaml.contains("relios release --skip-backup --no-open"))
        XCTAssertTrue(yaml.contains("dist/PortfolioManager.app"))
        XCTAssertTrue(yaml.contains("PortfolioManager-${TAG}.zip"))
    }

    // MARK: - ci.yml generation

    func test_swiftpm_specProducesSwiftTestCIWorkflow() throws {
        let fs = InMemoryFileSystem(
            files: ["/proj/relios.toml": assemblyTOML()],
            directories: ["/proj/Tests"]
        )
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/ci.yml")
        XCTAssertTrue(yaml.contains("name: CI"))
        XCTAssertTrue(yaml.contains("pull_request"))
        XCTAssertTrue(yaml.contains("swift build -c release"))
        XCTAssertTrue(yaml.contains("swift test --parallel"))
        XCTAssertTrue(yaml.contains("actions/cache@"))
        XCTAssertFalse(yaml.contains("xcodebuild"))
    }

    func test_swiftpm_specWithoutTestsDirectoryOmitsTestStep() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/ci.yml")
        XCTAssertTrue(yaml.contains("swift build -c release"))
        // `swift test` exits 1 when no tests exist — emitting the step
        // unconditionally turns "no tests yet" into a red build.
        XCTAssertFalse(yaml.contains("swift test"))
        XCTAssertTrue(yaml.contains("No Tests/ directory detected"))
    }

    func test_xcodebuild_specProducesXcodebuildCIWorkflowWithoutTests() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": passthroughTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/ci.yml")
        XCTAssertTrue(yaml.contains("name: CI"))
        XCTAssertTrue(yaml.contains("pull_request"))
        XCTAssertTrue(yaml.contains("xcodebuild -scheme MyApp"))
        // Tests are not emitted for xcodebuild (scheme unknown) — TODO comment lives in its place.
        XCTAssertTrue(yaml.contains("TODO: enable tests"))
        XCTAssertFalse(yaml.contains("swift test"))
    }

    // MARK: - Developer ID signing integration

    private func devIDSigningBlock() -> String {
        return """


        [signing]
        mode = "developer-id"
        identity = "Developer ID Application: Test (ABCDE12345)"
        team_id = "ABCDE12345"
        """
    }

    private func passthroughTOMLWithDevID() -> String {
        let base = passthroughTOML()
        let stripped = base.components(separatedBy: "\n[signing]").first ?? base
        return stripped + devIDSigningBlock()
    }

    func test_releaseWorkflow_omitsKeychainStepsWhenNotDeveloperID() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": passthroughTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertFalse(yaml.contains("security create-keychain"))
        XCTAssertFalse(yaml.contains("APPLE_CERTIFICATE"))
        XCTAssertFalse(yaml.contains("Delete signing keychain"))
    }

    func test_releaseWorkflow_injectsKeychainStepsForDeveloperID() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": passthroughTOMLWithDevID()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")

        XCTAssertTrue(yaml.contains("Import Developer ID certificate"))
        XCTAssertTrue(yaml.contains("${{ secrets.APPLE_CERTIFICATE }}"))
        XCTAssertTrue(yaml.contains("${{ secrets.APPLE_CERTIFICATE_PASSWORD }}"))
        XCTAssertTrue(yaml.contains("${{ secrets.KEYCHAIN_PASSWORD }}"))
        XCTAssertTrue(yaml.contains("security create-keychain"))
        XCTAssertTrue(yaml.contains("set-key-partition-list"))
        XCTAssertTrue(yaml.contains("security import"))
        XCTAssertTrue(yaml.contains("Delete signing keychain"))
        XCTAssertTrue(yaml.contains("if: always()"))
        XCTAssertTrue(yaml.contains("APPLE_CERTIFICATE           — base64-encoded"))

        // Regression: keychain block must not run into the next step's line.
        // Earlier bug produced `rm -f "$CERT_PATH"      - name: Install Relios`.
        XCTAssertFalse(yaml.contains("$CERT_PATH\"      "))
        XCTAssertFalse(yaml.contains("$CERT_PATH\"  -"))
    }

    // MARK: - DMG workflow integration

    func test_releaseWorkflow_omitsDMGStepsWhenDMGAbsent() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertFalse(yaml.contains("pip install"))
        XCTAssertFalse(yaml.contains("relios dmg"))
        XCTAssertFalse(yaml.contains("DMG_GLOB"))
    }

    func test_releaseWorkflow_includesDMGStepsWhenEnabled() throws {
        let toml = assemblyTOML() + """


        [dmg]
        enabled = true
        output_dir = "dist"
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertTrue(yaml.contains("pip install --break-system-packages dmgbuild"))
        XCTAssertTrue(yaml.contains("relios dmg"))
        XCTAssertTrue(yaml.contains("DMG_GLOB=dist/*.dmg"))
        XCTAssertTrue(yaml.contains("${{ env.DMG_GLOB }}"))
    }

    func test_releaseWorkflow_installsReliosForPassthroughWhenDMGEnabled() throws {
        // Passthrough normally skips Relios install, but DMG needs it.
        let toml = passthroughTOML() + """


        [dmg]
        enabled = true
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertTrue(yaml.contains("brew install papa-channy/relios/relios"))
        XCTAssertTrue(yaml.contains("xcodebuild"))
    }

    // MARK: - safety

    func test_missingSpecIsReported() {
        let fs = InMemoryFileSystem()
        let runner = CIInitRunner(fs: fs)

        XCTAssertThrowsError(try runner.run(projectRoot: "/proj", force: false)) { err in
            XCTAssertEqual(err as? CIError, .specMissing(path: "/proj/relios.toml"))
        }
    }

    func test_existingReleaseOnlyIsReported() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": passthroughTOML(),
            "/proj/.github/workflows/release.yml": "stale: true\n",
        ])
        XCTAssertThrowsError(try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)) { err in
            XCTAssertEqual(
                err as? CIError,
                .workflowExists(paths: ["/proj/.github/workflows/release.yml"])
            )
        }
    }

    func test_bothExistingWorkflowsListedTogether() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": passthroughTOML(),
            "/proj/.github/workflows/release.yml": "stale: true\n",
            "/proj/.github/workflows/ci.yml":      "stale: true\n",
        ])
        XCTAssertThrowsError(try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)) { err in
            XCTAssertEqual(
                err as? CIError,
                .workflowExists(paths: [
                    "/proj/.github/workflows/release.yml",
                    "/proj/.github/workflows/ci.yml",
                ])
            )
        }
        // Existing files untouched.
        XCTAssertEqual(try fs.readUTF8(at: "/proj/.github/workflows/release.yml"), "stale: true\n")
        XCTAssertEqual(try fs.readUTF8(at: "/proj/.github/workflows/ci.yml"),      "stale: true\n")
    }

    func test_forceOverwritesExistingWorkflows() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": passthroughTOML(),
            "/proj/.github/workflows/release.yml": "stale: true\n",
            "/proj/.github/workflows/ci.yml":      "stale: true\n",
        ])
        let result = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: true)

        XCTAssertTrue(result.files.allSatisfy { $0.overwritten })
        let release = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        let ci      = try fs.readUTF8(at: "/proj/.github/workflows/ci.yml")
        XCTAssertFalse(release.contains("stale"))
        XCTAssertFalse(ci.contains("stale"))
        XCTAssertTrue(release.contains("xcodebuild"))
        XCTAssertTrue(ci.contains("name: CI"))
    }
}
