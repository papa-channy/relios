import XCTest
import ReliosCore
import ReliosSupport

final class NotarizeTargetResolverTests: XCTestCase {

    // MARK: - auto

    func test_autoPicksDMGWhenEnabled() throws {
        let spec = try makeSpec(dmgEnabled: true, notarizeTarget: "auto")
        let fs = InMemoryFileSystem(files: ["/proj/dist/App-1.0.0.dmg": "dmg"])
        let resolved = try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: "1.0.0",
            explicitPath: nil
        )
        XCTAssertEqual(resolved, "/proj/dist/App-1.0.0.dmg")
    }

    func test_autoFallsBackToZipWhenNoDMG() throws {
        let spec = try makeSpec(dmgEnabled: false, notarizeTarget: "auto")
        let fs = InMemoryFileSystem(files: ["/proj/App-1.0.0.zip": "zip"])
        let resolved = try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: "1.0.0",
            explicitPath: nil
        )
        XCTAssertEqual(resolved, "/proj/App-1.0.0.zip")
    }

    // MARK: - explicit

    func test_explicitPathIsReturnedWhenExists() throws {
        let spec = try makeSpec(dmgEnabled: false, notarizeTarget: "auto")
        let fs = InMemoryFileSystem(files: ["/proj/custom/build.dmg": "x"])
        let resolved = try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: nil,
            explicitPath: "custom/build.dmg"
        )
        XCTAssertEqual(resolved, "/proj/custom/build.dmg")
    }

    func test_explicitPathRejectsNonZipNonDMG() throws {
        let spec = try makeSpec(dmgEnabled: false, notarizeTarget: "auto")
        let fs = InMemoryFileSystem(files: ["/proj/App.tar.gz": "x"])
        XCTAssertThrowsError(try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: nil,
            explicitPath: "App.tar.gz"
        )) { err in
            guard case NotarizeError.unsupportedArtifact = err else {
                return XCTFail("expected .unsupportedArtifact, got \(err)")
            }
        }
    }

    func test_explicitPathMissingIsReported() throws {
        let spec = try makeSpec(dmgEnabled: false, notarizeTarget: "auto")
        let fs = InMemoryFileSystem()
        XCTAssertThrowsError(try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: nil,
            explicitPath: "App.zip"
        )) { err in
            guard case NotarizeError.artifactMissing = err else {
                return XCTFail("expected .artifactMissing, got \(err)")
            }
        }
    }

    // MARK: - missing artifacts

    func test_zipMissingIsReported() throws {
        let spec = try makeSpec(dmgEnabled: false, notarizeTarget: "zip")
        let fs = InMemoryFileSystem()
        XCTAssertThrowsError(try NotarizeTargetResolver(fs: fs).resolve(
            spec: spec,
            projectRoot: "/proj",
            versionString: "1.0.0",
            explicitPath: nil
        )) { err in
            guard case NotarizeError.artifactMissing(let path) = err else {
                return XCTFail("expected .artifactMissing, got \(err)")
            }
            XCTAssertTrue(path.contains("App-1.0.0.zip"))
        }
    }

    // MARK: - helpers

    private func makeSpec(dmgEnabled: Bool, notarizeTarget: String) throws -> ReleaseSpec {
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
        mode = "developer-id"
        identity = "Developer ID Application: T (ABCDE12345)"
        team_id = "ABCDE12345"
        hardened_runtime = true
        entitlements_path = ""
        """
        if dmgEnabled {
            toml += "\n\n[dmg]\nenabled = true\noutput_dir = \"dist\""
        }
        toml += "\n\n[notarize]\nenabled = true\ntarget = \"\(notarizeTarget)\""
        let fs = InMemoryFileSystem(files: ["/s/relios.toml": toml])
        return try SpecLoader(fs: fs).load(from: "/s/relios.toml")
    }
}
