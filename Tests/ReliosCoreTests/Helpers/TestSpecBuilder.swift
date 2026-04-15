import ReliosCore
import ReliosSupport

/// Builds a ReleaseSpec through the real SpecLoader so tests stay insulated
/// from `ReleaseSpec`'s internal shape (it has no memberwise init).
enum TestSpecBuilder {
    static func spec(
        signingMode: SigningSection.Mode,
        identity: String? = nil,
        teamID: String? = nil,
        hardenedRuntime: Bool = true,
        entitlementsPath: String? = nil
    ) -> ReleaseSpec {
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
        output_path = "dist/X.app"
        plist_mode = "generate"

        [install]
        path = "/Applications/X.app"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "\(signingMode.rawValue)"
        identity = "\(identity ?? "")"
        team_id = "\(teamID ?? "")"
        hardened_runtime = \(hardenedRuntime ? "true" : "false")
        entitlements_path = "\(entitlementsPath ?? "")"
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        return try! SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }
}
