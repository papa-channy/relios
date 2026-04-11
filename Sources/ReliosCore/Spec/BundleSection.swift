public struct BundleSection: Decodable, Equatable, Sendable {
    public enum PlistMode: String, Decodable, Equatable, Sendable {
        case generate
    }

    public let outputPath: String
    public let plistMode: PlistMode

    private enum CodingKeys: String, CodingKey {
        case outputPath = "output_path"
        case plistMode  = "plist_mode"
    }
}
