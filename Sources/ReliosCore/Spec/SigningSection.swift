public struct SigningSection: Decodable, Equatable, Sendable {
    public enum Mode: String, Decodable, Equatable, Sendable {
        case adhoc
        /// Keep whatever signature the .app already has (or none).
        /// Primarily for passthrough mode where xcodebuild already signed.
        case keep
        /// Apple Developer ID signing. Requires `identity` + `team_id` and
        /// an identity that exists in the user's keychain.
        case developerID = "developer-id"
    }

    public let mode: Mode
    /// Codesigning identity name, e.g.
    /// "Developer ID Application: Chan (ABCDE12345)". Required when
    /// `mode == .developerID`, otherwise ignored.
    public let identity: String?
    /// 10-character Apple Team ID. Parsed from `identity`'s trailing
    /// parenthesis by `signing setup`, but stored explicitly so CI and
    /// notarization workflows can read it without re-parsing.
    public let teamID: String?
    /// Emit `--options runtime` when signing. Defaults to `true` because
    /// Developer ID binaries effectively require hardened runtime to be
    /// notarizable; only disable for local experimentation.
    public let hardenedRuntime: Bool
    /// Optional entitlements plist to pass via `--entitlements`.
    public let entitlementsPath: String?

    private enum CodingKeys: String, CodingKey {
        case mode
        case identity
        case teamID           = "team_id"
        case hardenedRuntime  = "hardened_runtime"
        case entitlementsPath = "entitlements_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try c.decode(Mode.self, forKey: .mode)
        self.identity = try Self.nilIfEmpty(c.decodeIfPresent(String.self, forKey: .identity))
        self.teamID = try Self.nilIfEmpty(c.decodeIfPresent(String.self, forKey: .teamID))
        self.hardenedRuntime = try c.decodeIfPresent(Bool.self, forKey: .hardenedRuntime) ?? true
        self.entitlementsPath = try Self.nilIfEmpty(c.decodeIfPresent(String.self, forKey: .entitlementsPath))
    }

    public init(
        mode: Mode,
        identity: String? = nil,
        teamID: String? = nil,
        hardenedRuntime: Bool = true,
        entitlementsPath: String? = nil
    ) {
        self.mode = mode
        self.identity = identity
        self.teamID = teamID
        self.hardenedRuntime = hardenedRuntime
        self.entitlementsPath = entitlementsPath
    }

    private static func nilIfEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
