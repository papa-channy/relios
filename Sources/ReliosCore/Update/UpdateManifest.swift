import Foundation

/// The auto-update feed the shipped app polls. Written as JSON to
/// `[update].output_dir/[update].feed_file` (default `dist/update.json`) and
/// published as a GitHub Release asset.
///
/// The app fetches this file, compares `version`/`build` against its own, and
/// — if newer — points the user at `url` (the artifact) and `notes_url` (the
/// release page). Field names are snake_case to read naturally from any
/// client that consumes the JSON, not just Swift.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let appName: String
    public let bundleId: String
    public let version: String
    public let build: String
    /// Direct download URL for the new artifact (DMG or zip).
    public let url: String
    /// Human-readable changelog for this version. `nil` if none was supplied.
    public let notes: String?
    /// Link to the full release page (GitHub Release). `nil` if unknown.
    public let notesURL: String?
    public let minMacOS: String
    public let publishedAt: String
    /// SHA-256 (hex) of the artifact, so the app can verify the download.
    public let sha256: String?
    /// Artifact size in bytes.
    public let size: Int?
    /// Git commit the release was built from (provenance). `nil` if unknown.
    public let gitCommit: String?

    public init(
        appName: String,
        bundleId: String,
        version: String,
        build: String,
        url: String,
        notes: String?,
        notesURL: String?,
        minMacOS: String,
        publishedAt: String,
        sha256: String? = nil,
        size: Int? = nil,
        gitCommit: String? = nil
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.version = version
        self.build = build
        self.url = url
        self.notes = notes
        self.notesURL = notesURL
        self.minMacOS = minMacOS
        self.publishedAt = publishedAt
        self.sha256 = sha256
        self.size = size
        self.gitCommit = gitCommit
    }

    private enum CodingKeys: String, CodingKey {
        case appName     = "app_name"
        case bundleId    = "bundle_id"
        case version
        case build
        case url
        case notes
        case notesURL    = "notes_url"
        case minMacOS    = "min_macos"
        case publishedAt = "published_at"
        case sha256
        case size
        case gitCommit   = "git_commit"
    }
}
