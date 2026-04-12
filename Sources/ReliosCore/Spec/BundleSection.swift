public struct BundleSection: Decodable, Equatable, Sendable {
    public enum PlistMode: String, Decodable, Equatable, Sendable {
        case generate
    }

    /// Controls whether Relios assembles a .app from scratch or treats
    /// `output_path` as a pre-built .app (e.g. from xcodebuild).
    public enum Mode: String, Decodable, Equatable, Sendable {
        /// Default: Relios copies the binary, resources, and icon into a
        /// freshly created .app bundle and generates Info.plist.
        case assembly
        /// The .app at `output_path` is already complete (built by
        /// xcodebuild or similar). Relios skips bundle assembly and
        /// Info.plist generation, and proceeds directly to signing,
        /// backup, install, and launch.
        case passthrough
    }

    public let outputPath: String
    public let plistMode: PlistMode
    /// Defaults to `.assembly` for backward compatibility with existing
    /// relios.toml files that don't specify this field.
    public let mode: Mode

    private enum CodingKeys: String, CodingKey {
        case outputPath = "output_path"
        case plistMode  = "plist_mode"
        case mode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.outputPath = try c.decode(String.self, forKey: .outputPath)
        self.plistMode  = try c.decode(PlistMode.self, forKey: .plistMode)
        self.mode       = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .assembly
    }
}
