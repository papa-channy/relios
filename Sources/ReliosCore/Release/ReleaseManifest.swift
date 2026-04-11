import Foundation

/// JSON model written after each successful non-dry-run release.
/// Stored at `dist/releases/latest.json` (overwritten each time)
/// and `dist/releases/history/<timestamp>.json` (append-only).
public struct ReleaseManifest: Codable, Equatable, Sendable {
    public let appName: String
    public let bundleId: String
    public let version: String
    public let build: String
    public let bundlePath: String
    public let installPath: String?
    public let backupPath: String?
    public let signingMode: String
    public let launchedAfterInstall: Bool
    public let timestamp: String

    public init(
        appName: String,
        bundleId: String,
        version: String,
        build: String,
        bundlePath: String,
        installPath: String?,
        backupPath: String?,
        signingMode: String,
        launchedAfterInstall: Bool,
        timestamp: String
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.version = version
        self.build = build
        self.bundlePath = bundlePath
        self.installPath = installPath
        self.backupPath = backupPath
        self.signingMode = signingMode
        self.launchedAfterInstall = launchedAfterInstall
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleId = "bundle_id"
        case version
        case build
        case bundlePath = "bundle_path"
        case installPath = "install_path"
        case backupPath = "backup_path"
        case signingMode = "signing_mode"
        case launchedAfterInstall = "launched_after_install"
        case timestamp
    }
}
