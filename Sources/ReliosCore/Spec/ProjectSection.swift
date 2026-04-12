public struct ProjectSection: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Equatable, Sendable {
        case swiftpm
        case xcodebuild
    }

    public let type: Kind
    public let root: String
    public let binaryTarget: String

    private enum CodingKeys: String, CodingKey {
        case type
        case root
        case binaryTarget = "binary_target"
    }
}
