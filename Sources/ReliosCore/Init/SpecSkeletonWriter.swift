import ReliosSupport

/// Renders a `SpecSkeleton` as TOML and writes it through the injected `FileSystem`.
///
/// `render(_:)` is `public` so tests can roundtrip:
///   `SpecSkeleton → render → SpecLoader.load → ReleaseSpec`
/// without ever touching disk.
public struct SpecSkeletonWriter: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func write(_ skeleton: SpecSkeleton, to path: String) throws {
        let toml = render(skeleton)
        do {
            try fs.writeUTF8(toml, to: path)
        } catch {
            throw InitError.writeFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }

    /// Generates a canonical `AppVersion.swift` that the version patterns
    /// in the TOML skeleton can immediately read. This is what makes
    /// `init → doctor → release --dry-run` work without manual file creation.
    public func writeVersionSource(_ skeleton: SpecSkeleton, to path: String) throws {
        let content = renderVersionSource(skeleton)
        do {
            try fs.writeUTF8(content, to: path)
        } catch {
            throw InitError.writeFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }

    public func renderVersionSource(_ s: SpecSkeleton) -> String {
        return """
        enum AppVersion {
            static let current = "0.1.0"
            static let build = "1"
        }
        """
    }

    public func render(_ s: SpecSkeleton) -> String {
        return """
        [app]
        name = "\(s.appName)"
        display_name = "\(s.appName)"
        bundle_id = "\(s.bundleId)"
        min_macos = "14.0"
        category = "public.app-category.developer-tools"

        [project]
        type = "swiftpm"
        root = "."
        binary_target = "\(s.binaryTarget)"

        [version]
        source_file = "AppVersion.swift"
        version_pattern = 'static let current = "(.*)"'
        build_pattern = 'static let build = "(.*)"'

        [build]
        command = "\(s.buildCommand)"
        binary_path = ".build/release/\(s.binaryTarget)"
        resource_bundle_path = ""

        [assets]
        icon_path = ""

        [bundle]
        output_path = "\(s.outputAppPath)"
        plist_mode = "generate"

        [install]
        path = "\(s.installPath)"
        auto_open = true
        backup_dir = "dist/app-backups"
        keep_backups = 3
        quit_running_app = true

        [signing]
        mode = "adhoc"
        """
    }
}
