public struct AppSection: Decodable, Equatable, Sendable {
    public let name: String
    public let displayName: String
    public let bundleId: String
    public let minMacOS: String
    public let category: String

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName  = "display_name"
        case bundleId     = "bundle_id"
        case minMacOS     = "min_macos"
        case category
    }
}
