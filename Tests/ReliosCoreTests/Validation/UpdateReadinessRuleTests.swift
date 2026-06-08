import XCTest
import ReliosCore
import ReliosSupport

final class UpdateReadinessRuleTests: XCTestCase {

    private func spec(updateBlock: String) throws -> ReleaseSpec {
        let toml = """
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
        version_pattern = 'v = "(.*)"'
        build_pattern = 'b = "(.*)"'

        [build]
        command = "swift build -c release"
        binary_path = ".build/release/Demo"
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "dist/Demo.app"
        plist_mode = "generate"

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
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    private func evaluate(_ spec: ReleaseSpec) -> RuleResult {
        let fs = InMemoryFileSystem()
        return UpdateReadinessRule().evaluate(
            ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
        )
    }

    func test_okWhenAbsent() throws {
        let result = evaluate(try spec(updateBlock: ""))
        guard case .ok = result else { return XCTFail("expected .ok, got \(result)") }
    }

    func test_okWhenDisabled() throws {
        let result = evaluate(try spec(updateBlock: "\n[update]\nenabled = false\n"))
        guard case .ok = result else { return XCTFail("expected .ok, got \(result)") }
    }

    func test_okWhenEnabledWithDefaultTemplate() throws {
        let result = evaluate(try spec(updateBlock: "\n[update]\nenabled = true\n"))
        guard case .ok(let title, _) = result else { return XCTFail("expected .ok, got \(result)") }
        XCTAssertEqual(title, "update feed configured")
    }

    func test_warnsWhenTemplateMissingPlaceholders() throws {
        let block = """

        [update]
        enabled = true
        download_url_template = "https://example.com/latest.dmg"
        """
        let result = evaluate(try spec(updateBlock: block))
        guard case .warn(_, let reason, _, _) = result else {
            return XCTFail("expected .warn, got \(result)")
        }
        XCTAssertTrue(reason.contains("{tag}"))
        XCTAssertTrue(reason.contains("{asset}"))
    }
}
