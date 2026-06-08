import XCTest
import ReliosCore
import ReliosSupport

/// `relios update generate`: build the update.json feed from the current version.
final class UpdateRunnerTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 0) // "1970-01-01T00:00:00Z"

    private func toml(updateBlock: String) -> String {
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
    }

    private func makeFS(updateBlock: String) -> InMemoryFileSystem {
        InMemoryFileSystem(files: [
            "/proj/relios.toml": toml(updateBlock: updateBlock),
            "/proj/AppVersion.swift": "v = \"2.0.1\"\nb = \"7\"",
        ])
    }

    private func loadSpec(_ fs: InMemoryFileSystem) throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    // Explicit --download-url is used verbatim; notes_url derived from repo+tag.
    func test_explicitDownloadURL_andDerivedNotesURL() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let spec = try loadSpec(fs)
        let runner = UpdateRunner(fs: fs)

        let result = try runner.run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(
                tag: "v2.0.1",
                repo: "o/r",
                downloadURL: "https://cdn.example.com/Demo.dmg",
                notes: "- changed"
            ),
            now: epoch
        )

        XCTAssertEqual(result.version, "2.0.1")
        XCTAssertEqual(result.build, "7")
        XCTAssertEqual(result.downloadURL, "https://cdn.example.com/Demo.dmg")
        XCTAssertEqual(result.manifestPath, "/proj/dist/update.json")

        let json = try fs.readUTF8(at: "/proj/dist/update.json")
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.url, "https://cdn.example.com/Demo.dmg")
        XCTAssertEqual(manifest.notesURL, "https://github.com/o/r/releases/tag/v2.0.1")
        XCTAssertEqual(manifest.version, "2.0.1")
        XCTAssertEqual(manifest.publishedAt, "1970-01-01T00:00:00Z")
        // Slashes are not escaped → URLs stay readable in the raw file.
        XCTAssertTrue(json.contains("https://cdn.example.com/Demo.dmg"))
    }

    // No explicit URL → built from the template with repo/tag/asset.
    func test_downloadURLFromTemplate() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let spec = try loadSpec(fs)
        let runner = UpdateRunner(fs: fs)

        let result = try runner.run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v2.0.1", repo: "o/r", asset: "Demo-2.0.1.dmg"),
            now: epoch
        )

        XCTAssertEqual(
            result.downloadURL,
            "https://github.com/o/r/releases/download/v2.0.1/Demo-2.0.1.dmg"
        )
    }

    // Custom template placeholders are honored.
    func test_customTemplate() throws {
        let block = """

        [update]
        enabled = true
        download_url_template = "https://dl.example.com/{tag}/{asset}"
        """
        let fs = makeFS(updateBlock: block)
        let spec = try loadSpec(fs)

        let result = try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v2.0.1", repo: "o/r", asset: "Demo.dmg"),
            now: epoch
        )
        XCTAssertEqual(result.downloadURL, "https://dl.example.com/v2.0.1/Demo.dmg")
    }

    // feed_url is surfaced in the result for the CLI to echo.
    func test_feedURLSurfaced() throws {
        let block = """

        [update]
        enabled = true
        feed_url = "https://github.com/o/r/releases/latest/download/update.json"
        """
        let fs = makeFS(updateBlock: block)
        let spec = try loadSpec(fs)

        let result = try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", downloadURL: "u"),
            now: epoch
        )
        XCTAssertEqual(result.feedURL, "https://github.com/o/r/releases/latest/download/update.json")
    }

    // --output overrides the spec-derived path.
    func test_outputOverride() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let spec = try loadSpec(fs)

        let result = try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", downloadURL: "u", outputOverride: "/tmp/feed.json"),
            now: epoch
        )
        XCTAssertEqual(result.manifestPath, "/tmp/feed.json")
        XCTAssertTrue(fs.fileExists(at: "/tmp/feed.json"))
    }

    // [update] absent → updateDisabled.
    func test_disabledWhenSectionAbsent() throws {
        let fs = makeFS(updateBlock: "")
        let spec = try loadSpec(fs)

        XCTAssertThrowsError(try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", downloadURL: "u"),
            now: epoch
        )) { error in
            XCTAssertEqual(error as? UpdateError, .updateDisabled)
        }
    }

    // enabled = false → updateDisabled.
    func test_disabledWhenFalse() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = false\n")
        let spec = try loadSpec(fs)

        XCTAssertThrowsError(try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", downloadURL: "u"),
            now: epoch
        )) { error in
            XCTAssertEqual(error as? UpdateError, .updateDisabled)
        }
    }

    // No explicit URL and no asset → downloadURLUnresolved.
    func test_unresolvedURLWhenNoExplicitOrAsset() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let spec = try loadSpec(fs)

        XCTAssertThrowsError(try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", repo: "o/r"),
            now: epoch
        )) { error in
            guard case .downloadURLUnresolved = (error as? UpdateError) else {
                return XCTFail("expected .downloadURLUnresolved, got \(error)")
            }
        }
    }

    // Unreadable version source → versionReadFailed.
    func test_versionReadFailure() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": toml(updateBlock: "\n[update]\nenabled = true\n"),
            "/proj/AppVersion.swift": "no match here",
        ])
        let spec = try loadSpec(fs)

        XCTAssertThrowsError(try UpdateRunner(fs: fs).run(
            spec: spec,
            projectRoot: "/proj",
            options: .init(tag: "v1.0.0", downloadURL: "u"),
            now: epoch
        )) { error in
            guard case .versionReadFailed = (error as? UpdateError) else {
                return XCTFail("expected .versionReadFailed, got \(error)")
            }
        }
    }
}
