import XCTest
import ReliosCore
import ReliosSupport

/// `[build].executable`/`arguments` runs the build WITHOUT a shell.
final class BuildArgvTests: XCTestCase {

    private func spec(buildBlock: String, fs: InMemoryFileSystem) throws -> ReleaseSpec {
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
        fs.seed("/proj/relios.toml", toml)
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    func test_argvBuildUsesNoShell() throws {
        let fs = InMemoryFileSystem(files: ["/proj/.build/release/X": "bin"])
        let spec = try spec(buildBlock: """
        [build]
        executable = "swift"
        arguments = ["build", "-c", "release"]
        binary_path = ".build/release/X"
        """, fs: fs)
        let process = MockProcessRunner(result: .success)

        try SwiftBuildRunner(process: process, fs: fs).runBuild(spec: spec, projectRoot: "/proj")

        // Took the argv path (recorded separately), with the right executable/args.
        XCTAssertEqual(process.argvCalls.count, 1)
        XCTAssertEqual(process.argvCalls.first?.executable, "swift")
        XCTAssertEqual(process.argvCalls.first?.arguments, ["build", "-c", "release"])
        XCTAssertEqual(spec.build.displayCommand, "swift build -c release")
        XCTAssertTrue(spec.build.usesArgv)
    }

    func test_shellBuildUsesRunShell() throws {
        let fs = InMemoryFileSystem(files: ["/proj/.build/release/X": "bin"])
        let spec = try spec(buildBlock: """
        [build]
        command = "swift build -c release"
        binary_path = ".build/release/X"
        """, fs: fs)
        let process = MockProcessRunner(result: .success)

        try SwiftBuildRunner(process: process, fs: fs).runBuild(spec: spec, projectRoot: "/proj")

        XCTAssertTrue(process.argvCalls.isEmpty, "shell command must not use the argv path")
        XCTAssertTrue(process.calls.contains { $0.command == "swift build -c release" })
        XCTAssertFalse(spec.build.usesArgv)
    }
}

private extension InMemoryFileSystem {
    func seed(_ path: String, _ content: String) {
        try? writeUTF8(content, to: path)
    }
}
