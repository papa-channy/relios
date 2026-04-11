public struct AssetsSection: Decodable, Equatable, Sendable {
    public let iconPath: String?

    private enum CodingKeys: String, CodingKey {
        case iconPath = "icon_path"
    }

    public init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .iconPath)
        self.iconPath = (raw?.isEmpty == false) ? raw : nil
    }
}
