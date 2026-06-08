import XCTest
import ReliosCore
import ReliosSupport

final class PathSafetyRuleTests: XCTestCase {

    private func spec(output: String, install: String) throws -> ReleaseSpec {
        let toml = """
        [app]
        name = "X"
        display_name = "X"
        bundle_id = "com.example.x"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"
        [project]
        type = "swiftpm"
        root = "."
        binary_target = "X"
        [version]
        source_file = "X.swift"
        version_pattern = 'v = "(.*)"'
        build_pattern = 'b = "(.*)"'
        [build]
        command = "swift build -c release"
        binary_path = ".build/release/X"
        resource_bundle_path = ""
        [assets]
        icon_path = ""
        [bundle]
        output_path = "\(output)"
        plist_mode = "generate"
        mode = "assembly"
        [install]
        path = "\(install)"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true
        [signing]
        mode = "adhoc"
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    private func evaluate(output: String, install: String) throws -> RuleResult {
        let spec = try spec(output: output, install: install)
        let fs = InMemoryFileSystem()
        let ctx = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
        return PathSafetyRule(homeDir: "/Users/me").evaluate(ctx)
    }

    func test_okForNormalPaths() throws {
        let r = try evaluate(output: "dist/X.app", install: "/Applications/X.app")
        guard case .ok = r else { return XCTFail("expected .ok, got \(r)") }
    }

    func test_failsWhenOutputEscapesRoot() throws {
        let r = try evaluate(output: "../../etc/X.app", install: "/Applications/X.app")
        XCTAssertEqual(r.code, DiagnosticCode("PATH_OUTPUT_ESCAPES_ROOT"))
    }

    func test_failsWhenInstallNotApp() throws {
        let r = try evaluate(output: "dist/X.app", install: "/Applications/X")
        XCTAssertEqual(r.code, DiagnosticCode("PATH_INSTALL_NOT_APP"))
    }

    func test_failsWhenInstallDangerous() throws {
        let r = try evaluate(output: "dist/X.app", install: "/Users/me")
        // /Users/me is home (dangerous) but also not .app → not-app fires first; both are failures.
        XCTAssertEqual(r.severity, .fail)
    }

    func test_failsWhenInstallIsHomeAppBundle() throws {
        let r = try evaluate(output: "dist/X.app", install: "/Users/me/../me")
        // normalizes to /Users/me — dangerous; not .app so NOT_APP fires.
        XCTAssertEqual(r.severity, .fail)
    }

    func test_failsWhenOutputEqualsInstall() throws {
        let r = try evaluate(output: "X.app", install: "/proj/X.app")
        XCTAssertEqual(r.code, DiagnosticCode("PATH_OUTPUT_EQUALS_INSTALL"))
    }
}
