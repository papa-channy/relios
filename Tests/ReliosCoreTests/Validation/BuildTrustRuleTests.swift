import XCTest
import ReliosCore
import ReliosSupport

final class BuildTrustRuleTests: XCTestCase {

    private func spec(buildBlock: String) throws -> ReleaseSpec {
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
        \(buildBlock)
        [assets]
        icon_path = ""
        [bundle]
        output_path = "dist/X.app"
        plist_mode = "generate"
        mode = "assembly"
        [install]
        path = "/Applications/X.app"
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

    private func evaluate(_ buildBlock: String) throws -> RuleResult {
        let ctx = ValidationContext(spec: try spec(buildBlock: buildBlock), projectRoot: "/proj", fs: InMemoryFileSystem())
        return BuildTrustRule().evaluate(ctx)
    }

    func test_argvFormIsOk() throws {
        let r = try evaluate("""
        [build]
        executable = "swift"
        arguments = ["build", "-c", "release"]
        binary_path = ".build/release/X"
        """)
        XCTAssertEqual(r.severity, .ok)
        XCTAssertEqual(r.code, DiagnosticCode("BUILD_TRUST_OK"))
    }

    func test_shellCommandWarns() throws {
        let r = try evaluate("""
        [build]
        command = "swift build -c release"
        binary_path = ".build/release/X"
        """)
        XCTAssertEqual(r.severity, .warn)
        XCTAssertEqual(r.code, DiagnosticCode("BUILD_SHELL_COMMAND"))
    }

    func test_shellCommandWithAllowShellIsOk() throws {
        let r = try evaluate("""
        [build]
        command = "swift build -c release"
        allow_shell = true
        binary_path = ".build/release/X"
        """)
        XCTAssertEqual(r.severity, .ok)
    }

    func test_missingBuildCommandFails() throws {
        let r = try evaluate("""
        [build]
        command = ""
        binary_path = ".build/release/X"
        """)
        XCTAssertEqual(r.severity, .fail)
        XCTAssertEqual(r.code, DiagnosticCode("BUILD_COMMAND_MISSING"))
    }
}
