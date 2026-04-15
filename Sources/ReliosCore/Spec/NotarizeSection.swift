/// Optional `[notarize]` section in relios.toml. Absent or `enabled = false`
/// → notarization is skipped.
///
/// Credentials (`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`)
/// are **never** in the TOML — they come from the environment. That keeps
/// relios.toml commit-safe and matches the CI secret pattern.
public struct NotarizeSection: Decodable, Equatable, Sendable {
    public enum Target: String, Decodable, Equatable, Sendable {
        /// Prefer DMG if `[dmg].enabled`; otherwise fall back to the zip
        /// produced by `relios release`.
        case auto
        case dmg
        case zip
    }

    public let enabled: Bool
    public let target: Target
    /// Max wait for `xcrun notarytool submit --wait`. Apple averages 2-5 min
    /// but spikes to 15+ during load; 1800s (30 min) is the safe default.
    public let timeoutSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case enabled
        case target
        case timeoutSeconds = "timeout_seconds"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled        = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.target         = try c.decodeIfPresent(Target.self, forKey: .target) ?? .auto
        self.timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 1800
    }

    public init(enabled: Bool = true, target: Target = .auto, timeoutSeconds: Int = 1800) {
        self.enabled = enabled
        self.target = target
        self.timeoutSeconds = timeoutSeconds
    }
}
