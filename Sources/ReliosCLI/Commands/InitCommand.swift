import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct InitCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Generate a relios.toml skeleton in the current project."
    )

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()

        let scanner = ProjectScanner(fs: fs)
        let scan: ProjectScanResult
        do {
            scan = try scanner.scan(root: root)
        } catch let error as InitError {
            printInitFailure(error)
            throw ExitCode.failure
        }

        var skeleton = SpecSkeleton.from(scan: scan)

        // Auto-populate Developer ID signing when the keychain has exactly
        // one "Developer ID Application" identity. Zero or multiple → leave
        // mode=adhoc; the summary explains why. This is the one-shot flow:
        // register the cert in Keychain Access (or `relios signing import`)
        // once, then any future `relios init` picks it up automatically.
        let keychainOutcome = detectDeveloperIDIdentity()
        if case .single(let identity, let teamID) = keychainOutcome {
            skeleton = skeleton.withDeveloperID(identity: identity, teamID: teamID)
        }

        let writer = SpecSkeletonWriter(fs: fs)

        var createdFiles: [String] = []

        // 1. Write relios.toml
        let specPath = root + "/relios.toml"
        do {
            try writer.write(skeleton, to: specPath)
            createdFiles.append("relios.toml")
        } catch let error as InitError {
            printInitFailure(error)
            throw ExitCode.failure
        }

        // 2. Write AppVersion.swift (only if it doesn't already exist)
        let versionSourcePath = root + "/AppVersion.swift"
        if !fs.fileExists(at: versionSourcePath) {
            do {
                try writer.writeVersionSource(skeleton, to: versionSourcePath)
                createdFiles.append("AppVersion.swift")
            } catch let error as InitError {
                printInitFailure(error)
                throw ExitCode.failure
            }
        }

        printSummary(skeleton, createdFiles: createdFiles, keychain: keychainOutcome)
    }

    // MARK: - keychain probe

    private enum KeychainOutcome {
        case single(identity: String, teamID: String)
        case none
        case multiple(count: Int)
        case ambiguousNoTeam(identity: String)
        case unavailable
    }

    private func detectDeveloperIDIdentity() -> KeychainOutcome {
        let process = RealProcessRunner()
        guard let identities = try? KeychainIdentityLister(process: process).list() else {
            return .unavailable
        }
        let devIDs = identities.filter { $0.name.contains("Developer ID Application") }
        switch devIDs.count {
        case 0:
            return .none
        case 1:
            guard let teamID = devIDs[0].teamID else {
                return .ambiguousNoTeam(identity: devIDs[0].name)
            }
            return .single(identity: devIDs[0].name, teamID: teamID)
        default:
            return .multiple(count: devIDs.count)
        }
    }

    // MARK: - output

    private func printSummary(_ s: SpecSkeleton, createdFiles: [String], keychain: KeychainOutcome) {
        print("✓ Initialized Relios")
        print("")
        print("Created files:")
        for file in createdFiles {
            print("  \(file)")
        }
        print("")
        print("Detected:")
        print("  project type:  \(s.projectType.rawValue)")
        print("  binary target: \(s.binaryTarget)")
        if s.bundleMode == .passthrough {
            print("  bundle mode:   passthrough (Xcode project)")
        }
        switch keychain {
        case .single(let identity, let teamID):
            print("  signing:       developer-id (\(teamID))")
            print("                 \(identity)")
        case .none:
            print("  signing:       adhoc (no Developer ID cert in keychain)")
        case .multiple(let count):
            print("  signing:       adhoc (\(count) Developer ID certs found — ambiguous;")
            print("                 run `relios signing setup` to pick one)")
        case .ambiguousNoTeam(let identity):
            print("  signing:       adhoc (cert found but Team ID unparseable)")
            print("                 \(identity)")
        case .unavailable:
            print("  signing:       adhoc (could not query keychain)")
        }
        print("")
        print("Review before first release:")
        print("  [app].bundle_id      (currently \(s.bundleId))")
        if createdFiles.contains("AppVersion.swift") {
            print("  AppVersion.swift     (generated with 0.1.0 build 1)")
        }
        if s.projectType == .xcodebuild {
            print("  [build].command      (verify scheme name matches your project)")
            print("  [bundle].output_path (MUST match where xcodebuild places the .app)")
            print("")
            print("  Note: scheme name was guessed from the .xcodeproj filename.")
            print("  If your scheme name differs, update [build].command and")
            print("  [bundle].output_path accordingly.")
        }
        print("  [assets].icon_path   (currently empty)")
        print("")
        print("Next step:")
        print("  relios doctor")
    }

    private func printInitFailure(_ error: InitError) {
        print("[init] failed")
        print("  Reason: \(error.shortReason)")
        print("  Fix: \(error.shortFix)")
    }
}
