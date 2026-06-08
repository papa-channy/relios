import XCTest
import ReliosCore
import ReliosSupport

/// Locks the auto-update integration in generated workflows:
///   - release.yml gains an update-manifest step + feed asset when [update] on
///   - auto-release.yml is generated only when [update] is enabled
final class CIUpdateWorkflowTests: XCTestCase {

    private func assemblyTOML(updateBlock: String = "") -> String {
        """
        [app]
        name = "Demo"
        display_name = "Demo"
        bundle_id = "com.example.demo"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"

        [project]
        type = "swiftpm"
        root = "."
        binary_target = "Demo"

        [version]
        source_file = "AppVersion.swift"
        version_pattern = 'static let current = "(.*)"'
        build_pattern = 'static let build = "(.*)"'

        [build]
        command = "swift build -c release"
        binary_path = ".build/release/Demo"
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "dist/Demo.app"
        plist_mode = "generate"
        mode = "assembly"

        [install]
        path = "/Applications/Demo.app"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "adhoc"
        \(updateBlock)
        """
    }

    // MARK: - release.yml injection

    func test_releaseWorkflow_omitsUpdateStepsWhenAbsent() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertFalse(yaml.contains("Generate update manifest"))
        XCTAssertFalse(yaml.contains("relios update generate"))
        XCTAssertFalse(yaml.contains("fetch-depth: 0"))
    }

    func test_releaseWorkflow_injectsUpdateStepsWhenEnabled() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
        ])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")

        XCTAssertTrue(yaml.contains("Generate update manifest"))
        XCTAssertTrue(yaml.contains("relios update generate"))
        XCTAssertTrue(yaml.contains("--download-url"))
        XCTAssertTrue(yaml.contains("--notes-file"))
        // Full history for git-log-based release notes.
        XCTAssertTrue(yaml.contains("fetch-depth: 0"))
        // Feed file is uploaded with the release.
        XCTAssertTrue(yaml.contains("dist/update.json"))
        XCTAssertTrue(yaml.contains("files: |"))
        // Update step lands before publish.
        let updateIdx  = yaml.range(of: "Generate update manifest")!.lowerBound
        let publishIdx = yaml.range(of: "Publish GitHub Release")!.lowerBound
        XCTAssertTrue(updateIdx < publishIdx, "update step must precede publish")
    }

    func test_releaseWorkflow_isHardenedWhenUpdateEnabled() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
        ])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")

        // least-privilege top-level + escalated job
        XCTAssertTrue(yaml.contains("permissions:\n  contents: read"))
        XCTAssertTrue(yaml.contains("permissions:\n      contents: write"))
        // concurrency guard
        XCTAssertTrue(yaml.contains("concurrency:"))
        XCTAssertTrue(yaml.contains("relios-release-"))
        // tag == version verification
        XCTAssertTrue(yaml.contains("Verify tag matches AppVersion"))
        // provenance + integrity + signing wired into the update step
        XCTAssertTrue(yaml.contains("--artifact"))
        XCTAssertTrue(yaml.contains("--commit"))
        XCTAssertTrue(yaml.contains("RELIOS_UPDATE_SIGNING_KEY"))
        // signature uploaded with the release
        XCTAssertTrue(yaml.contains("dist/update.json.sig"))
    }

    func test_ciWorkflow_hasLeastPrivilegePermissions() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/ci.yml")
        XCTAssertTrue(yaml.contains("permissions:\n  contents: read"))
    }

    func test_autoReleaseWorkflow_isHardened() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
        ])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/auto-release.yml")
        XCTAssertTrue(yaml.contains("permissions:\n  contents: read"))
        XCTAssertTrue(yaml.contains("contents: write"))   // job-level escalation
        XCTAssertTrue(yaml.contains("concurrency:"))
    }

    func test_releaseWorkflow_respectsCustomFeedFileName() throws {
        let block = """

        [update]
        enabled = true
        feed_file = "appcast.json"
        output_dir = "public"
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML(updateBlock: block)])
        _ = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
        XCTAssertTrue(yaml.contains("public/appcast.json"))
    }

    // MARK: - auto-release.yml

    func test_autoReleaseWorkflow_notGeneratedWhenUpdateAbsent() throws {
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
        let result = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertFalse(fs.fileExists(at: "/proj/.github/workflows/auto-release.yml"))
    }

    func test_autoReleaseWorkflow_generatedWhenUpdateEnabled() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
        ])
        let result = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)

        XCTAssertEqual(result.files.count, 3)
        XCTAssertEqual(result.files.last?.path, "/proj/.github/workflows/auto-release.yml")

        let yaml = try fs.readUTF8(at: "/proj/.github/workflows/auto-release.yml")
        XCTAssertTrue(yaml.contains("name: Auto Release"))
        XCTAssertTrue(yaml.contains("branches: [main]"))
        XCTAssertTrue(yaml.contains("VERSION=$(relios version)"))
        XCTAssertTrue(yaml.contains("git rev-parse \"$TAG\""))
        XCTAssertTrue(yaml.contains("git push origin \"$TAG\""))
        XCTAssertTrue(yaml.contains("contents: write"))
    }

    func test_autoReleaseWorkflow_conflictDetectedWithoutForce() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
            "/proj/.github/workflows/auto-release.yml": "stale: true\n",
        ])
        XCTAssertThrowsError(try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: false)) { err in
            guard case .workflowExists(let paths) = (err as? CIError) else {
                return XCTFail("expected .workflowExists, got \(String(describing: err))")
            }
            XCTAssertTrue(paths.contains("/proj/.github/workflows/auto-release.yml"))
        }
        // Untouched without --force.
        XCTAssertEqual(try fs.readUTF8(at: "/proj/.github/workflows/auto-release.yml"), "stale: true\n")
    }

    func test_autoReleaseWorkflow_overwrittenWithForce() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": assemblyTOML(updateBlock: "\n[update]\nenabled = true\n"),
            "/proj/.github/workflows/auto-release.yml": "stale: true\n",
        ])
        let result = try CIInitRunner(fs: fs).run(projectRoot: "/proj", force: true)
        // Only auto-release.yml pre-existed; it must be reported as overwritten.
        let autoFile = result.files.first { $0.path.hasSuffix("auto-release.yml") }
        XCTAssertEqual(autoFile?.overwritten, true)
        XCTAssertFalse(try fs.readUTF8(at: "/proj/.github/workflows/auto-release.yml").contains("stale"))
    }
}
