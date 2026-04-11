import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct InspectCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Show the latest release manifest and the currently installed app's state."
    )

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let releasesDir = root + "/dist/releases"

        let reader = InspectReader(fs: fs)
        let manifest: ReleaseManifest
        do {
            manifest = try reader.readLatest(releasesDir: releasesDir)
        } catch let error as ManifestError {
            switch error {
            case .latestNotFound:
                print("[inspect] No release manifest found.")
                print("  Run `relios release` first.")
                throw ExitCode.failure
            case .decodingFailed(_, let reason):
                print("[inspect] Could not read release manifest: \(reason)")
                throw ExitCode.failure
            case .encodingFailed:
                print("[inspect] Unexpected error.")
                throw ExitCode.failure
            }
        }

        print("Latest Release")
        print("")
        print("  App:       \(manifest.appName)")
        print("  Bundle ID: \(manifest.bundleId)")
        print("  Version:   \(manifest.version) (build \(manifest.build))")
        print("  Bundle:    \(manifest.bundlePath)")
        if let ip = manifest.installPath {
            print("  Install:   \(ip)")
        }
        if let bp = manifest.backupPath {
            print("  Backup:    \(bp)")
        }
        print("  Signing:   \(manifest.signingMode)")
        print("  Launched:  \(manifest.launchedAfterInstall ? "yes" : "no")")
        print("  Timestamp: \(manifest.timestamp)")
    }
}
