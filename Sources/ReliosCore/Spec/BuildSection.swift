public struct BuildSection: Decodable, Equatable, Sendable {
    public let command: String
    public let binaryPath: String
    public let resourceBundlePath: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case binaryPath         = "binary_path"
        case resourceBundlePath = "resource_bundle_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.command    = try c.decode(String.self, forKey: .command)
        self.binaryPath = try c.decode(String.self, forKey: .binaryPath)
        let raw = try c.decodeIfPresent(String.self, forKey: .resourceBundlePath)
        self.resourceBundlePath = (raw?.isEmpty == false) ? raw : nil
    }
}
