import XCTest
import ReliosCore
import ReliosSupport

final class NotarizeReadinessRuleTests: XCTestCase {

    func test_skippedWhenNotarizeAbsent() throws {
        let (ctx, env) = try makeContext(notarizeTOML: nil, env: [:], notarytoolOK: true)
        let result = NotarizeReadinessRule(env: env).evaluate(ctx)
        guard case .ok(let title) = result else { return XCTFail("expected .ok") }
        XCTAssertTrue(title.contains("skipped"))
    }

    func test_skippedWhenNotarizeDisabled() throws {
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = false\n",
            env: [:],
            notarytoolOK: true
        )
        guard case .ok = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .ok")
        }
    }

    func test_failsWhenSigningModeIsAdhoc() throws {
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = true\n",
            env: fullEnv,
            notarytoolOK: true,
            signingMode: "adhoc"
        )
        guard case .fail(_, let reason, _) = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .fail")
        }
        XCTAssertTrue(reason.contains("developer-id"))
    }

    func test_failsWhenNotarytoolMissing() throws {
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = true\n",
            env: fullEnv,
            notarytoolOK: false
        )
        guard case .fail(let title, _, _) = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .fail")
        }
        XCTAssertEqual(title, "notarytool not available")
    }

    func test_warnsWhenCredentialsMissing() throws {
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = true\n",
            env: [:],
            notarytoolOK: true
        )
        guard case .warn(_, let reason, _) = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .warn")
        }
        XCTAssertTrue(reason.contains("APPLE_ID"))
    }

    func test_warnsOnTeamIDMismatch() throws {
        var envDict = fullEnv
        envDict["APPLE_TEAM_ID"] = "ZZZZZZZZZZ"
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = true\n",
            env: envDict,
            notarytoolOK: true
        )
        guard case .warn(let title, _, _) = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .warn")
        }
        XCTAssertEqual(title, "team_id mismatch")
    }

    func test_okWhenAllGood() throws {
        let (ctx, env) = try makeContext(
            notarizeTOML: "[notarize]\nenabled = true\n",
            env: fullEnv,
            notarytoolOK: true
        )
        guard case .ok = NotarizeReadinessRule(env: env).evaluate(ctx) else {
            return XCTFail("expected .ok")
        }
    }

    // MARK: - helpers

    private let fullEnv: [String: String] = [
        "APPLE_ID": "dev@example.com",
        "APPLE_APP_SPECIFIC_PASSWORD": "pw",
        "APPLE_TEAM_ID": "ABCDE12345",
    ]

    private func makeContext(
        notarizeTOML: String?,
        env: [String: String],
        notarytoolOK: Bool,
        signingMode: String = "developer-id"
    ) throws -> (ValidationContext, [String: String]) {
        var toml = """
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
        mode = "\(signingMode)"
        identity = "Developer ID Application: T (ABCDE12345)"
        team_id = "ABCDE12345"
        hardened_runtime = true
        entitlements_path = ""
        """
        if let n = notarizeTOML { toml += "\n\n" + n }
        let fs = InMemoryFileSystem(files: ["/p/relios.toml": toml])
        let spec = try SpecLoader(fs: fs).load(from: "/p/relios.toml")
        let runner = MockProcessRunner(result: ProcessResult(
            exitCode: notarytoolOK ? 0 : 1,
            stdout: "",
            stderr: ""
        ))
        return (
            ValidationContext(spec: spec, projectRoot: "/p", fs: fs, process: runner),
            env
        )
    }
}
