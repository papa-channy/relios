import XCTest
import ReliosCore
import ReliosSupport
import Foundation

/// Feed integrity (sha256/size/commit) and Ed25519 signing in UpdateRunner.
final class UpdateIntegrityTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 0)

    private func makeFS(updateBlock: String, artifact: (path: String, content: String)? = nil) -> InMemoryFileSystem {
        var files: [String: String] = [
            "/proj/relios.toml": toml(updateBlock: updateBlock),
            "/proj/AppVersion.swift": "v = \"2.0.1\"\nb = \"7\"",
        ]
        if let artifact { files[artifact.path] = artifact.content }
        return InMemoryFileSystem(files: files)
    }

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

    private func spec(_ fs: InMemoryFileSystem) throws -> ReleaseSpec {
        try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }

    func test_artifactHashAndSizeAndCommit() throws {
        let content = "DMG-BYTES"
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n",
                        artifact: ("/proj/dist/Demo-2.0.1.dmg", content))
        let result = try UpdateRunner(fs: fs).run(
            spec: try spec(fs), projectRoot: "/proj",
            options: .init(tag: "v2.0.1", downloadURL: "u",
                           artifactPath: "/proj/dist/Demo-2.0.1.dmg", gitCommit: "abc123"),
            now: epoch
        )

        XCTAssertEqual(result.sha256, FeedSigner.sha256Hex(Data(content.utf8)))
        let json = try fs.readUTF8(at: "/proj/dist/update.json")
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.sha256, FeedSigner.sha256Hex(Data(content.utf8)))
        XCTAssertEqual(manifest.size, content.utf8.count)
        XCTAssertEqual(manifest.gitCommit, "abc123")
    }

    func test_signedFeedWritesSigThatVerifies() throws {
        let pair = FeedSigner.generateKeyPair()
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let result = try UpdateRunner(fs: fs).run(
            spec: try spec(fs), projectRoot: "/proj",
            options: .init(tag: "v2.0.1", downloadURL: "u", signingKeyBase64: pair.privateKeyBase64),
            now: epoch
        )

        XCTAssertEqual(result.signaturePath, "/proj/dist/update.json.sig")
        let json = try fs.readUTF8(at: "/proj/dist/update.json")
        let sig = try fs.readUTF8(at: "/proj/dist/update.json.sig").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            FeedSigner.verify(Data(json.utf8), signatureBase64: sig, publicKeyBase64: pair.publicKeyBase64),
            "the .sig must verify against the exact update.json bytes"
        )
    }

    func test_unsignedWhenNoKey() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\n")
        let result = try UpdateRunner(fs: fs).run(
            spec: try spec(fs), projectRoot: "/proj",
            options: .init(tag: "v2.0.1", downloadURL: "u"),
            now: epoch
        )
        XCTAssertNil(result.signaturePath)
        XCTAssertFalse(fs.fileExists(at: "/proj/dist/update.json.sig"))
    }

    func test_signingKeyMissingWarnsWhenSignTrue() throws {
        let fs = makeFS(updateBlock: "\n[update]\nenabled = true\nsign = true\n")
        let ctx = ValidationContext(spec: try spec(fs), projectRoot: "/proj", fs: InMemoryFileSystem())
        // env without the key
        let result = UpdateReadinessRule(env: [:]).evaluate(ctx)
        XCTAssertEqual(result.code, DiagnosticCode("UPDATE_SIGNING_KEY_MISSING"))
        // with the key → ok
        let ok = UpdateReadinessRule(env: ["RELIOS_UPDATE_SIGNING_KEY": "x"]).evaluate(ctx)
        XCTAssertEqual(ok.severity, .ok)
    }
}
