/// Optional `[update]` section in relios.toml. Absent or `enabled = false`
/// → no auto-update feed is generated.
///
/// The feed is a small JSON manifest (`update.json`) that the shipped app
/// polls to learn whether a newer version exists. `relios update generate`
/// writes it; the release workflow uploads it as a GitHub Release asset so
/// the app can fetch it from a stable URL
/// (`https://github.com/<owner>/<repo>/releases/latest/download/update.json`).
public struct UpdateSection: Decodable, Equatable, Sendable {
    public let enabled: Bool
    /// Filename of the generated manifest. Defaults to `update.json`.
    public let feedFileName: String
    /// Directory the manifest is written to locally. Defaults to `dist`.
    public let outputDir: String
    /// Template used to build the artifact download URL when an explicit
    /// `--download-url` isn't passed. Placeholders: `{repo}` (owner/repo),
    /// `{tag}` (e.g. v2.0.1), `{asset}` (artifact filename).
    public let downloadURLTemplate: String
    /// Public URL the app polls. Informational — recorded so `doctor` and
    /// `update generate` can echo where to point the app. `nil` if unset.
    public let feedURL: String?
    /// Opt in to Ed25519-signing the feed. When true, `doctor` warns if no
    /// signing key (`RELIOS_UPDATE_SIGNING_KEY`) is available.
    public let sign: Bool

    private enum CodingKeys: String, CodingKey {
        case enabled
        case feedFileName        = "feed_file"
        case outputDir           = "output_dir"
        case downloadURLTemplate = "download_url_template"
        case feedURL             = "feed_url"
        case sign
    }

    public static let defaultDownloadURLTemplate =
        "https://github.com/{repo}/releases/download/{tag}/{asset}"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled             = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.feedFileName        = try Self.nonEmpty(c.decodeIfPresent(String.self, forKey: .feedFileName)) ?? "update.json"
        self.outputDir           = try Self.nonEmpty(c.decodeIfPresent(String.self, forKey: .outputDir)) ?? "dist"
        self.downloadURLTemplate = try Self.nonEmpty(c.decodeIfPresent(String.self, forKey: .downloadURLTemplate)) ?? Self.defaultDownloadURLTemplate
        self.feedURL             = try Self.nonEmpty(c.decodeIfPresent(String.self, forKey: .feedURL))
        self.sign                = try c.decodeIfPresent(Bool.self, forKey: .sign) ?? false
    }

    public init(
        enabled: Bool = true,
        feedFileName: String = "update.json",
        outputDir: String = "dist",
        downloadURLTemplate: String = UpdateSection.defaultDownloadURLTemplate,
        feedURL: String? = nil,
        sign: Bool = false
    ) {
        self.enabled = enabled
        self.feedFileName = feedFileName
        self.outputDir = outputDir
        self.downloadURLTemplate = downloadURLTemplate
        self.feedURL = feedURL
        self.sign = sign
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
