public struct SigningSection: Decodable, Equatable, Sendable {
    public enum Mode: String, Decodable, Equatable, Sendable {
        case adhoc
        /// Keep whatever signature the .app already has (or none).
        /// Primarily for passthrough mode where xcodebuild already signed.
        case keep
    }

    public let mode: Mode
}
