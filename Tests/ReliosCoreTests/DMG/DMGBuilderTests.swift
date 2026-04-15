import XCTest
import ReliosCore
import ReliosSupport

/// Covers the DMG slice:
///   - settings renderer output (centering math, guide invariants)
///   - DMGBuilder orchestration (dmgbuild call, stale .dmg purge, cleanup)
///   - error surfaces (disabled, app missing, dmgbuild not found)
final class DMGBuilderTests: XCTestCase {

    // MARK: - settings renderer

    func test_settingsRenderer_usesGuideInvariants() {
        let dmg = DMGSection()
        let yaml = DMGSettingsRenderer().render(dmg, appBundleName: "MyApp.app")

        // Solid color — no background image (guide Problem 1).
        XCTAssertTrue(yaml.contains("background_color = '#FCF5F3'"))
        // No volume icon (guide Problem 2).
        XCTAssertFalse(yaml.contains("icon = '"))
        XCTAssertTrue(yaml.contains("# No volume icon"))
        // Icon view + chrome off.
        XCTAssertTrue(yaml.contains("default_view    = 'icon-view'"))
        XCTAssertTrue(yaml.contains("show_sidebar    = False"))
        // DMGBUILD_APP_PATH env indirection so the settings file doesn't
        // hardcode the .app location.
        XCTAssertTrue(yaml.contains("os.environ['DMGBUILD_APP_PATH']"))
    }

    func test_settingsRenderer_centersIconsAroundWindowMidpoint() {
        // 540-wide window → app at 150, apps at 390 (guide reference values).
        let dmg = DMGSection(windowWidth: 540, windowHeight: 360)
        let yaml = DMGSettingsRenderer().render(dmg, appBundleName: "X.app")
        XCTAssertTrue(yaml.contains("(150, 155)"))
        XCTAssertTrue(yaml.contains("(390, 155)"))
    }

    // MARK: - builder

    func test_builder_failsWhenDMGDisabled() throws {
        let fs = InMemoryFileSystem()
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)
        let spec = makeSpec(dmg: DMGSection(enabled: false))

        XCTAssertThrowsError(try builder.run(spec: spec, projectRoot: "/p", version: nil)) { err in
            XCTAssertEqual(err as? DMGError, .disabled)
        }
    }

    func test_builder_failsWhenDMGSectionAbsent() throws {
        let fs = InMemoryFileSystem()
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)
        let spec = makeSpec(dmg: nil)

        XCTAssertThrowsError(try builder.run(spec: spec, projectRoot: "/p", version: nil)) { err in
            XCTAssertEqual(err as? DMGError, .disabled)
        }
    }

    func test_builder_failsWhenAppMissing() throws {
        let fs = InMemoryFileSystem()
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)
        let spec = makeSpec(dmg: DMGSection())

        XCTAssertThrowsError(try builder.run(spec: spec, projectRoot: "/p", version: nil)) { err in
            XCTAssertEqual(err as? DMGError, .appMissing(path: "/p/dist/MyApp.app"))
        }
    }

    func test_builder_failsWhenDmgbuildNotInPath() throws {
        let fs = InMemoryFileSystem(directories: ["/p/dist/MyApp.app"])
        let runner = MockProcessRunner(result: .success)
        runner.commandOverrides["command -v dmgbuild"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        let builder = DMGBuilder(fs: fs, process: runner)

        XCTAssertThrowsError(try builder.run(
            spec: makeSpec(dmg: DMGSection()),
            projectRoot: "/p",
            version: nil
        )) { err in
            XCTAssertEqual(err as? DMGError, .dmgbuildNotFound)
        }
    }

    func test_builder_invokesDmgbuildWithCorrectArgs() throws {
        let fs = InMemoryFileSystem(directories: ["/p/dist/MyApp.app"])
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)

        let output = try builder.run(
            spec: makeSpec(dmg: DMGSection()),
            projectRoot: "/p",
            version: "1.2.3"
        )

        XCTAssertEqual(output.dmgPath, "/p/dist/MyApp-1.2.3.dmg")

        let dmgInvocation = runner.calls.first { $0.command.contains("dmgbuild") && !$0.command.contains("command -v") }
        guard let call = dmgInvocation else {
            return XCTFail("expected a dmgbuild invocation, got: \(runner.calls)")
        }
        XCTAssertTrue(call.command.contains("DMGBUILD_APP_PATH='/p/dist/MyApp.app'"))
        XCTAssertTrue(call.command.contains("'/p/dist/_dmg-settings.py'"))
        XCTAssertTrue(call.command.contains("'MyApp'"))                        // volume name defaults to app name
        XCTAssertTrue(call.command.contains("'/p/dist/MyApp-1.2.3.dmg'"))
        XCTAssertEqual(call.cwd, "/p")
    }

    func test_builder_purgesExistingDMGsBeforeBuilding() throws {
        // Pre-seed a stale DMG (guide Problem 4 — Tauri's broken DMG).
        var files: [String: String] = [
            "/p/dist/stale.dmg": "OLD",
            "/p/dist/bundle_dmg.sh": "stale script",
        ]
        files["/p/dist/.keep"] = ""
        let fs = InMemoryFileSystem(files: files, directories: ["/p/dist/MyApp.app"])
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)

        _ = try builder.run(
            spec: makeSpec(dmg: DMGSection()),
            projectRoot: "/p",
            version: nil
        )

        XCTAssertFalse(fs.fileExists(at: "/p/dist/stale.dmg"))
    }

    func test_builder_cleansUpSettingsFileOnSuccess() throws {
        let fs = InMemoryFileSystem(directories: ["/p/dist/MyApp.app"])
        let runner = MockProcessRunner(result: .success)
        let builder = DMGBuilder(fs: fs, process: runner)

        _ = try builder.run(
            spec: makeSpec(dmg: DMGSection()),
            projectRoot: "/p",
            version: nil
        )

        XCTAssertFalse(fs.fileExists(at: "/p/dist/_dmg-settings.py"))
    }

    func test_builder_surfacesDmgbuildExitCode() throws {
        let fs = InMemoryFileSystem(directories: ["/p/dist/MyApp.app"])
        let runner = MockProcessRunner(result: .success)
        runner.commandOverrides["DMGBUILD_APP_PATH"] = ProcessResult(
            exitCode: 2,
            stdout: "",
            stderr: "layout write failed"
        )
        let builder = DMGBuilder(fs: fs, process: runner)

        XCTAssertThrowsError(try builder.run(
            spec: makeSpec(dmg: DMGSection()),
            projectRoot: "/p",
            version: nil
        )) { err in
            XCTAssertEqual(err as? DMGError, .dmgbuildFailed(exitCode: 2, stderr: "layout write failed"))
        }
    }

    // MARK: - helpers

    private func makeSpec(dmg: DMGSection?) -> ReleaseSpec {
        let toml = """
        [app]
        name = "MyApp"
        display_name = "MyApp"
        bundle_id = "com.example.myapp"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"

        [project]
        type = "swiftpm"
        root = "."
        binary_target = "MyApp"

        [version]
        source_file = "AppVersion.swift"
        version_pattern = 'static let current = "(.*)"'
        build_pattern = 'static let build = "(.*)"'

        [build]
        command = "swift build -c release"
        binary_path = ".build/release/MyApp"
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "dist/MyApp.app"
        plist_mode = "generate"
        mode = "assembly"

        [install]
        path = "/Applications/MyApp.app"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "adhoc"
        """
        let withDmg: String
        if let dmg {
            withDmg = toml + """


            [dmg]
            enabled = \(dmg.enabled)
            output_dir = "\(dmg.outputDir)"
            background_color = "\(dmg.backgroundColor)"
            window_size = [\(dmg.windowWidth), \(dmg.windowHeight)]
            icon_size = \(dmg.iconSize)
            """
        } else {
            withDmg = toml
        }
        let fs = InMemoryFileSystem(files: ["/s/relios.toml": withDmg])
        return try! SpecLoader(fs: fs).load(from: "/s/relios.toml")
    }
}
