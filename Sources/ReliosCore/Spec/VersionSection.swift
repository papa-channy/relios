public struct VersionSection: Decodable, Equatable, Sendable {
    public let sourceFile: String
    public let versionPattern: String
    public let buildPattern: String

    private enum CodingKeys: String, CodingKey {
        case sourceFile     = "source_file"
        case versionPattern = "version_pattern"
        case buildPattern   = "build_pattern"
    }
}
