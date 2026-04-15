import XCTest
import ReliosCore
import ReliosSupport

/// Covers the three rules powering `relios ci doctor`:
///   - ReleaseWorkflowPresenceRule (fail when missing)
///   - CIWorkflowPresenceRule      (warn when missing)
///   - GitHubRemoteRule            (warn when not a git repo / no github remote)
final class CIDoctorRulesTests: XCTestCase {

    // MARK: - release workflow

    func test_releaseWorkflow_failsWhenMissing() throws {
        let ctx = try makeContext(files: [:])
        let r = ReleaseWorkflowPresenceRule().evaluate(ctx)
        guard case .fail(_, let reason, let fix) = r else {
            return XCTFail("expected .fail, got \(r)")
        }
        XCTAssertTrue(reason.contains("release.yml"))
        XCTAssertTrue(fix.contains("relios ci init"))
    }

    func test_releaseWorkflow_okWhenPresent() throws {
        let ctx = try makeContext(files: [
            "/proj/.github/workflows/release.yml": "name: Release\n",
        ])
        let r = ReleaseWorkflowPresenceRule().evaluate(ctx)
        guard case .ok = r else { return XCTFail("expected .ok, got \(r)") }
    }

    // MARK: - ci workflow

    func test_ciWorkflow_warnsWhenMissing() throws {
        let ctx = try makeContext(files: [:])
        let r = CIWorkflowPresenceRule().evaluate(ctx)
        guard case .warn(_, let reason, _) = r else {
            return XCTFail("expected .warn, got \(r)")
        }
        XCTAssertTrue(reason.contains("ci.yml"))
    }

    func test_ciWorkflow_okWhenPresent() throws {
        let ctx = try makeContext(files: [
            "/proj/.github/workflows/ci.yml": "name: CI\n",
        ])
        let r = CIWorkflowPresenceRule().evaluate(ctx)
        guard case .ok = r else { return XCTFail("expected .ok, got \(r)") }
    }

    // MARK: - github remote

    func test_githubRemote_warnsWhenNotAGitRepo() throws {
        let ctx = try makeContext(files: [:])
        let r = GitHubRemoteRule().evaluate(ctx)
        guard case .warn(_, let reason, _) = r else {
            return XCTFail("expected .warn, got \(r)")
        }
        XCTAssertTrue(reason.contains("Not a git repository"))
    }

    func test_githubRemote_warnsWhenConfigHasNoGithubURL() throws {
        let ctx = try makeContext(files: [
            "/proj/.git/config": """
            [remote "origin"]
                url = git@gitlab.com:me/app.git
            """,
        ])
        let r = GitHubRemoteRule().evaluate(ctx)
        guard case .warn(let title, _, _) = r else {
            return XCTFail("expected .warn, got \(r)")
        }
        XCTAssertEqual(title, "github remote")
    }

    func test_githubRemote_okWhenGithubURLPresent() throws {
        let ctx = try makeContext(files: [
            "/proj/.git/config": """
            [remote "origin"]
                url = https://github.com/me/app.git
            """,
        ])
        let r = GitHubRemoteRule().evaluate(ctx)
        guard case .ok = r else { return XCTFail("expected .ok, got \(r)") }
    }

    // MARK: - helpers

    private func makeContext(files: [String: String]) throws -> ValidationContext {
        var all = files
        let toml = minimalTOML
        all["/proj/relios.toml"] = toml
        let fs = InMemoryFileSystem(files: all)
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
    }

    private let minimalTOML = """
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
