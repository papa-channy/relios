import Foundation
import ReliosSupport

/// Orchestrates the release sequence.
///
/// **Dry-run path** (steps 1-5): read-only, zero writes (Gate 5 invariant).
/// **Non-dry-run path** (steps 1-9): writes to version source, assembles
/// .app bundle in dist/, generates Info.plist, signs ad-hoc.
///
/// Steps deliberately NOT here yet:
///   - backup existing app, terminate running app, install, launch, manifest
public struct ReleasePipeline: Sendable {
    private let fs: any FileSystem
    private let process: any ProcessRunner

    public init(fs: any FileSystem, process: any ProcessRunner) {
        self.fs = fs
        self.process = process
    }

    public func run(
        spec: ReleaseSpec,
        projectRoot: String,
        options: ReleaseOptions
    ) throws -> ReleaseSummary {
        // Steps 1-5: shared by dry-run and non-dry-run
        try preflightValidation(spec: spec, projectRoot: projectRoot)

        let (currentVersion, currentBuild) = try readCurrentVersion(
            spec: spec,
            projectRoot: projectRoot
        )

        let (nextVersion, nextBuild) = computeNextVersion(
            current: currentVersion,
            currentBuild: currentBuild,
            bump: options.bump
        )

        try runBuild(spec: spec, projectRoot: projectRoot)

        let binaryPath = try verifyBuildArtifact(
            spec: spec,
            projectRoot: projectRoot
        )

        // Dry-run: stop here, NO writes.
        if options.dryRun {
            return ReleaseSummary(
                appName: spec.app.name,
                previousVersion: currentVersion,
                previousBuild: currentBuild,
                nextVersion: nextVersion,
                nextBuild: nextBuild,
                buildCommand: spec.build.command,
                binaryPath: binaryPath,
                dryRun: true
            )
        }

        // Steps 6-9: non-dry-run only — these write to disk.
        try updateVersionSource(
            spec: spec,
            projectRoot: projectRoot,
            version: nextVersion,
            build: nextBuild
        )

        let outputPath = projectRoot + "/" + spec.bundle.outputPath
        try assembleAppBundle(
            spec: spec,
            binarySourcePath: binaryPath,
            outputPath: outputPath,
            projectRoot: projectRoot
        )

        try writeInfoPlist(
            spec: spec,
            version: nextVersion,
            build: nextBuild,
            outputPath: outputPath
        )

        try signAdhoc(appPath: outputPath)

        // Steps 10-13: install phase
        let installPath = options.installPath ?? spec.install.path

        var backupZipPath: String? = nil
        if !options.skipBackup {
            backupZipPath = try backupExistingApp(
                spec: spec,
                installPath: installPath,
                previousVersion: currentVersion,
                previousBuild: currentBuild
            )
        }

        if spec.install.quitRunningApp {
            try terminateRunningApp(spec: spec, installPath: installPath)
        }

        try installApp(from: outputPath, to: installPath)

        var launched = false
        if spec.install.autoOpen && !options.noOpen {
            try launchApp(at: installPath)
            launched = true
        }

        // Step 14: write release manifest
        try writeReleaseManifest(
            spec: spec,
            projectRoot: projectRoot,
            version: nextVersion,
            build: nextBuild,
            bundlePath: outputPath,
            installPath: installPath,
            backupPath: backupZipPath,
            launched: launched
        )

        return ReleaseSummary(
            appName: spec.app.name,
            previousVersion: currentVersion,
            previousBuild: currentBuild,
            nextVersion: nextVersion,
            nextBuild: nextBuild,
            buildCommand: spec.build.command,
            binaryPath: binaryPath,
            dryRun: false,
            bundlePath: outputPath,
            installedAt: installPath,
            backupPath: backupZipPath,
            launched: launched
        )
    }

    // MARK: - shared steps (1-5)

    private func preflightValidation(spec: ReleaseSpec, projectRoot: String) throws {
        let context = ValidationContext(
            spec: spec,
            projectRoot: projectRoot,
            fs: fs,
            process: process
        )
        let rules: [any ValidationRule] = [
            SpecValidityRule(),
            VersionSourceRule(),
            BuildReadinessRule(),
            SigningReadinessRule(),
        ]
        for rule in rules {
            let result = rule.evaluate(context)
            if case .fail(let title, let reason, let fix) = result {
                throw ReleaseError.preflightFailed(
                    ruleTitle: title,
                    reason: reason,
                    fix: fix
                )
            }
        }
    }

    private func readCurrentVersion(
        spec: ReleaseSpec,
        projectRoot: String
    ) throws -> (SemanticVersion, BuildNumber) {
        let reader = VersionSourceReader(fs: fs)
        let path = projectRoot + "/" + spec.version.sourceFile
        do {
            let result = try reader.read(spec: spec.version, at: path)
            return (result.version, result.build)
        } catch let error as VersionSourceError {
            throw ReleaseError.versionReadFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func computeNextVersion(
        current: SemanticVersion,
        currentBuild: BuildNumber,
        bump: BumpKind
    ) -> (SemanticVersion, BuildNumber) {
        let nextVersion = current.bumped(bump)
        let nextBuild: BuildNumber
        switch bump {
        case .none:
            nextBuild = currentBuild.incremented()
        case .patch, .minor, .major:
            nextBuild = .initial
        }
        return (nextVersion, nextBuild)
    }

    private func runBuild(spec: ReleaseSpec, projectRoot: String) throws {
        let runner = SwiftBuildRunner(process: process, fs: fs)
        do {
            try runner.runBuild(spec: spec, projectRoot: projectRoot)
        } catch let error as BuildError {
            throw ReleaseError.buildFailed(
                reason: error.shortReason,
                fix: error.shortFix,
                stderrTail: error.stderrTail
            )
        }
    }

    private func verifyBuildArtifact(
        spec: ReleaseSpec,
        projectRoot: String
    ) throws -> String {
        let runner = SwiftBuildRunner(process: process, fs: fs)
        do {
            return try runner.locateBinary(spec: spec, projectRoot: projectRoot)
        } catch BuildError.binaryNotFound(let searched) {
            throw ReleaseError.artifactNotFound(searched: searched)
        } catch {
            throw ReleaseError.artifactNotFound(searched: [])
        }
    }

    // MARK: - non-dry-run steps (6-9)

    private func updateVersionSource(
        spec: ReleaseSpec,
        projectRoot: String,
        version: SemanticVersion,
        build: BuildNumber
    ) throws {
        let updater = VersionSourceUpdater(fs: fs)
        let path = projectRoot + "/" + spec.version.sourceFile
        do {
            try updater.update(
                at: path,
                versionPattern: spec.version.versionPattern,
                newVersion: version,
                buildPattern: spec.version.buildPattern,
                newBuild: build
            )
        } catch let error as VersionSourceError {
            throw ReleaseError.versionUpdateFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func assembleAppBundle(
        spec: ReleaseSpec,
        binarySourcePath: String,
        outputPath: String,
        projectRoot: String
    ) throws {
        let assembler = AppBundleAssembler(fs: fs)
        do {
            _ = try assembler.assemble(
                spec: spec,
                binarySourcePath: binarySourcePath,
                outputPath: outputPath,
                projectRoot: projectRoot
            )
        } catch let error as BundleError {
            throw ReleaseError.bundleAssemblyFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func writeInfoPlist(
        spec: ReleaseSpec,
        version: SemanticVersion,
        build: BuildNumber,
        outputPath: String
    ) throws {
        let writer = InfoPlistWriter(fs: fs)
        let contentsPath = outputPath + "/Contents"
        do {
            try writer.write(
                spec: spec,
                version: version,
                build: build,
                toContentsDir: contentsPath
            )
        } catch let error as BundleError {
            throw ReleaseError.plistWriteFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func signAdhoc(appPath: String) throws {
        let signer = AdhocSigner(process: process)
        do {
            try signer.sign(appPath: appPath)
        } catch let error as SigningError {
            throw ReleaseError.signingFailed(
                reason: error.shortReason,
                fix: error.shortFix,
                stderrTail: {
                    if case .nonZeroExit(_, let tail) = error { return tail }
                    return nil
                }()
            )
        }
    }

    // MARK: - install steps (10-13)

    private func backupExistingApp(
        spec: ReleaseSpec,
        installPath: String,
        previousVersion: SemanticVersion,
        previousBuild: BuildNumber
    ) throws -> String? {
        let archiver = DittoArchiveWriter(process: process)
        let manager = BackupManager(fs: fs, archiver: archiver)
        do {
            return try manager.backup(
                installedAppPath: installPath,
                backupDir: spec.install.backupDir,
                keepBackups: spec.install.keepBackups,
                appName: spec.app.name,
                version: previousVersion.formatted,
                build: previousBuild.formatted
            )
        } catch let error as InstallError {
            throw ReleaseError.backupFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func terminateRunningApp(spec: ReleaseSpec, installPath: String) throws {
        let terminator = RunningAppTerminator(process: process)
        do {
            _ = try terminator.terminate(
                bundleId: spec.app.bundleId,
                installedAppPath: installPath,
                executableName: spec.app.name
            )
        } catch let error as InstallError {
            throw ReleaseError.terminateFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func installApp(from source: String, to destination: String) throws {
        let installer = AppInstaller(fs: fs)
        do {
            try installer.install(from: source, to: destination)
        } catch let error as InstallError {
            throw ReleaseError.installFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    private func launchApp(at path: String) throws {
        let launcher = AppLauncher(process: process)
        do {
            try launcher.launch(appPath: path)
        } catch let error as InstallError {
            throw ReleaseError.launchFailed(
                reason: error.shortReason,
                fix: error.shortFix
            )
        }
    }

    // MARK: - manifest step (14)

    private func writeReleaseManifest(
        spec: ReleaseSpec,
        projectRoot: String,
        version: SemanticVersion,
        build: BuildNumber,
        bundlePath: String,
        installPath: String,
        backupPath: String?,
        launched: Bool
    ) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let timestamp = iso.string(from: Date())

        let manifest = ReleaseManifest(
            appName: spec.app.name,
            bundleId: spec.app.bundleId,
            version: version.formatted,
            build: build.formatted,
            bundlePath: bundlePath,
            installPath: installPath,
            backupPath: backupPath,
            signingMode: spec.signing.mode.rawValue,
            launchedAfterInstall: launched,
            timestamp: timestamp
        )

        let releasesDir = projectRoot + "/dist/releases"
        let writer = ReleaseManifestWriter(fs: fs)
        do {
            try writer.write(manifest, releasesDir: releasesDir)
        } catch {
            throw ReleaseError.manifestWriteFailed(
                reason: "Could not write release manifest: \(error)",
                fix: "Check directory permissions for dist/releases/"
            )
        }
    }
}
