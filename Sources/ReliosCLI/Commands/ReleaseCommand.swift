import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct ReleaseCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Build, package, sign, and install the app locally."
    )

    /// CLI-side enum for parsing. Translated to `ReliosCore.BumpKind` before
    /// the pipeline runs — this keeps `ReliosCore` from importing ArgumentParser.
    public enum CLIBumpKind: String, ExpressibleByArgument, CaseIterable {
        case patch
        case minor
        case major
    }

    @Argument(help: "Version bump: patch | minor | major. If omitted, only the build number increments.")
    public var bump: CLIBumpKind?

    @Flag(name: .long, help: "Build and package only — skip install.")
    public var dryRun: Bool = false

    @Flag(name: .long, help: "Do not auto-launch after install.")
    public var noOpen: Bool = false

    @Option(name: .long, help: "Override [install].path from relios.toml.")
    public var installPath: String?

    @Flag(name: .long, help: "Skip backup of the currently installed app.")
    public var skipBackup: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let process = RealProcessRunner()
        let specPath = root + "/relios.toml"

        // Load spec
        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            printSpecLoadFailure(error)
            throw ExitCode.failure
        }

        let options = ReleaseOptions(
            bump: coreBumpKind(),
            dryRun: dryRun,
            noOpen: noOpen,
            installPath: installPath,
            skipBackup: skipBackup,
            verbose: verbose
        )

        // Run pipeline
        let pipeline = ReleasePipeline(fs: fs, process: process)
        let summary: ReleaseSummary
        do {
            summary = try pipeline.run(spec: spec, projectRoot: root, options: options)
        } catch let error as ReleaseError {
            printReleaseFailure(error)
            throw ExitCode.failure
        }

        printReleaseSummary(summary)
    }

    // MARK: - bump translation

    private func coreBumpKind() -> BumpKind {
        switch bump {
        case .none:         return .none
        case .some(.patch): return .patch
        case .some(.minor): return .minor
        case .some(.major): return .major
        }
    }

    // MARK: - output

    private func printReleaseSummary(_ s: ReleaseSummary) {
        let prevLabel = "\(s.previousVersion.formatted) (build \(s.previousBuild.formatted))"
        let nextLabel = "\(s.nextVersion.formatted) (build \(s.nextBuild.formatted))"

        print("✓ Preflight passed")
        print("✓ Version: \(prevLabel) → \(nextLabel)")
        print("✓ Build completed")

        if s.passthrough {
            print("✓ Verified .app exists")
        } else {
            print("✓ Verified build artifact")
        }

        if s.dryRun {
            print("")
            print("Dry run — no files were written.")
        } else {
            print("✓ Updated version source")

            if !s.passthrough {
                print("✓ Assembled .app bundle")
                print("✓ Generated Info.plist")
            }

            switch s.signingMode {
            case "adhoc":  print("✓ Signed (ad-hoc)")
            case "keep":   break  // silence — nothing to report
            default:       print("✓ Signed (\(s.signingMode))")
            }

            if s.backupPath != nil {
                print("✓ Backed up previous app")
            }
            if let installAt = s.installedAt {
                print("✓ Installed to \(installAt)")
            }
            if s.launched {
                print("✓ Launched \(s.appName)")
            }
        }

        // Summary block — always shown
        print("")
        if let bp = s.bundlePath {
            print("  Bundle:  \(bp)")
        }
        if let ip = s.installedAt {
            print("  Install: \(ip)")
        }
        if let backup = s.backupPath {
            print("  Backup:  \(backup)")
        }
    }

    private func printReleaseFailure(_ error: ReleaseError) {
        print("[release] failed at: \(error.step.label)")
        print("  Reason: \(error.reason)")
        print("  Fix: \(error.fix)")
        if verbose, let tail = error.stderrTail, !tail.isEmpty {
            print("")
            print("--- stderr (tail) ---")
            print(tail)
        }
    }

    private func printSpecLoadFailure(_ error: SpecLoadError) {
        print("[release] failed at: spec load")
        print("  Reason: \(error.shortReason)")
        print("  Fix: \(error.shortFix)")
    }
}
