import XCTest
import ReliosCore
import ReliosSupport

final class DMGReadinessRuleTests: XCTestCase {

    func test_skippedWhenDMGAbsent() throws {
        let ctx = try makeContext(dmgTOML: nil, dmgbuildExitCode: 0)
        guard case .ok(let title) = DMGReadinessRule().evaluate(ctx) else {
            return XCTFail("expected .ok")
        }
        XCTAssertTrue(title.contains("skipped"))
    }

    func test_skippedWhenDMGDisabled() throws {
        let ctx = try makeContext(dmgTOML: "[dmg]\nenabled = false\n", dmgbuildExitCode: 0)
        guard case .ok(let title) = DMGReadinessRule().evaluate(ctx) else {
            return XCTFail("expected .ok")
        }
        XCTAssertTrue(title.contains("skipped"))
    }

    func test_okWhenDmgbuildAvailable() throws {
        let ctx = try makeContext(dmgTOML: "[dmg]\nenabled = true\n", dmgbuildExitCode: 0)
        guard case .ok(let title) = DMGReadinessRule().evaluate(ctx) else {
            return XCTFail("expected .ok")
        }
        XCTAssertEqual(title, "dmgbuild available")
    }

    func test_warnsWhenDmgbuildMissing() throws {
        let ctx = try makeContext(dmgTOML: "[dmg]\nenabled = true\n", dmgbuildExitCode: 1)
        guard case .warn(_, let reason, let fix) = DMGReadinessRule().evaluate(ctx) else {
            return XCTFail("expected .warn")
        }
        XCTAssertTrue(reason.contains("dmgbuild"))
        XCTAssertTrue(fix.contains("pip install"))
    }

    // MARK: - helpers

    private func makeContext(dmgTOML: String?, dmgbuildExitCode: Int32) throws -> ValidationContext {
        var toml = baseTOML
        if let dmgTOML { toml += "\n" + dmgTOML }
        let fs = InMemoryFileSystem(files: ["/p/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/p/relios.toml")
        let runner = MockProcessRunner(result: ProcessResult(exitCode: dmgbuildExitCode, stdout: "", stderr: ""))
        return ValidationContext(spec: spec, projectRoot: "/p", fs: fs, process: runner)
    }

    private let baseTOML = """
    [app]
    name = "App"
    display_name = "App"
    bundle_id = "com.example.app"
    min_macos = "14.0"
    category = "public.app-category.developer-tools"

    [project]
    type = "swiftpm"
    root = "."
    binary_target = "App"

    [version]
    source_file = "AppVersion.swift"
    version_pattern = 'static let current = "(.*)"'
    build_pattern = 'static let build = "(.*)"'

    [build]
    command = "swift build -c release"
    binary_path = ".build/release/App"
    resource_bundle_path = ""

    [assets]
    icon_path = ""

    [bundle]
    output_path = "dist/App.app"
    plist_mode = "generate"
    mode = "assembly"

    [install]
    path = "/Applications/App.app"
    auto_open = true
    backup_dir = "dist/app-backups"
    keep_backups = 3
    quit_running_app = true

    [signing]
    mode = "adhoc"
    """
}
