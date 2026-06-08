import Foundation
import ReliosSupport

/// Installs the most-recently-built `.app` without rebuilding.
///
/// This is the install half of `ReleasePipeline` (steps 10-14) lifted into a
/// standalone command. It does **not** build, bump the version, or re-sign —
/// it takes the `.app` already sitting at `[bundle].output_path` and installs it.
///
/// Flow:
///   1. Verify the `.app` exists at `[bundle].output_path`
///   2. Read current version (for backup naming + manifest — no bump)
///   3. Back up the currently installed app (unless `skipBackup`)
///   4. Terminate the running app (if `[install].quit_running_app`)
///   5. Install to `[install].path`
///   6. Launch (if `[install].auto_open` and not `noOpen`)
///   7. Write the release manifest
public struct InstallRunner: Sendable {
    private let fs: any FileSystem
    private let process: any ProcessRunner

    public init(fs: any FileSystem, process: any ProcessRunner) {
        self.fs = fs
        self.process = process
    }

    public struct Result: Sendable, Equatable, Encodable {
        public let bundlePath: String
        public let installedAt: String
        public let backupPath: String?
        public let launched: Bool
        public let version: String
        public let build: String

        private enum CodingKeys: String, CodingKey {
            case bundlePath = "bundle_path"
            case installedAt = "installed_at"
            case backupPath = "backup_path"
            case launched
            case version
            case build
        }
    }

    public func run(
        spec: ReleaseSpec,
        projectRoot: String,
        installPathOverride: String?,
        skipBackup: Bool,
        noOpen: Bool,
        now: Date = Date()
    ) throws -> Result {
        let bundlePath = projectRoot + "/" + spec.bundle.outputPath

        // 1. Verify the .app exists — there is nothing to install otherwise.
        guard fs.isDirectory(at: bundlePath) else {
            throw InstallError.appNotFound(path: bundlePath)
        }

        // 2. Read current version (no bump) for backup naming + manifest.
        let (version, build) = try readVersion(spec: spec, projectRoot: projectRoot)

        let installPath = installPathOverride ?? spec.install.path

        // Path safety: never replace a non-.app / protected target, and never
        // let output and install resolve to the same location.
        do {
            try PathSafety.assertAppBundle(installPath)
            try PathSafety.assertSafeDestructiveTarget(installPath, projectRoot: projectRoot, homeDir: NSHomeDirectory())
            try PathSafety.assertDistinct(installPath, bundlePath)
        } catch {
            throw InstallError.unsafePath(reason: String(describing: error))
        }

        // 3. Back up the currently installed app.
        var backupZipPath: String? = nil
        if !skipBackup {
            let archiver = DittoArchiveWriter(process: process)
            let manager = BackupManager(fs: fs, archiver: archiver)
            backupZipPath = try manager.backup(
                installedAppPath: installPath,
                backupDir: spec.install.backupDir,
                keepBackups: spec.install.keepBackups,
                appName: spec.app.name,
                version: version.formatted,
                build: build.formatted
            )
        }

        // 4. Terminate the running app.
        if spec.install.quitRunningApp {
            let terminator = RunningAppTerminator(process: process)
            _ = try terminator.terminate(
                bundleId: spec.app.bundleId,
                installedAppPath: installPath,
                executableName: spec.app.name
            )
        }

        // 5. Install.
        let installer = AppInstaller(fs: fs)
        try installer.install(from: bundlePath, to: installPath)

        // 6. Launch.
        var launched = false
        if spec.install.autoOpen && !noOpen {
            let launcher = AppLauncher(process: process)
            try launcher.launch(appPath: installPath)
            launched = true
        }

        // 7. Write the release manifest.
        try writeManifest(
            spec: spec,
            projectRoot: projectRoot,
            version: version,
            build: build,
            bundlePath: bundlePath,
            installPath: installPath,
            backupPath: backupZipPath,
            launched: launched,
            now: now
        )

        return Result(
            bundlePath: bundlePath,
            installedAt: installPath,
            backupPath: backupZipPath,
            launched: launched,
            version: version.formatted,
            build: build.formatted
        )
    }

    // MARK: - private

    private func readVersion(
        spec: ReleaseSpec,
        projectRoot: String
    ) throws -> (SemanticVersion, BuildNumber) {
        let reader = VersionSourceReader(fs: fs)
        let path = projectRoot + "/" + spec.version.sourceFile
        do {
            let result = try reader.read(spec: spec.version, at: path)
            return (result.version, result.build)
        } catch let error as VersionSourceError {
            throw InstallError.versionReadFailed(reason: error.shortReason)
        }
    }

    private func writeManifest(
        spec: ReleaseSpec,
        projectRoot: String,
        version: SemanticVersion,
        build: BuildNumber,
        bundlePath: String,
        installPath: String,
        backupPath: String?,
        launched: Bool,
        now: Date
    ) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let timestamp = iso.string(from: now)

        let manifest = ReleaseManifest(
            appName: spec.app.name,
            bundleId: spec.app.bundleId,
            version: version.formatted,
            build: build.formatted,
            bundlePath: bundlePath,
            installPath: installPath,
            backupPath: backupPath,
            signingMode: spec.signing.mode.rawValue,
            bundleMode: spec.bundle.mode.rawValue,
            launchedAfterInstall: launched,
            timestamp: timestamp
        )

        let releasesDir = projectRoot + "/dist/releases"
        let writer = ReleaseManifestWriter(fs: fs)
        try writer.write(manifest, releasesDir: releasesDir)
    }
}
