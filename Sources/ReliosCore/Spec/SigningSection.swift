public struct SigningSection: Decodable, Equatable, Sendable {
    public enum Mode: String, Decodable, Equatable, Sendable {
        case adhoc
    }

    public let mode: Mode
}
