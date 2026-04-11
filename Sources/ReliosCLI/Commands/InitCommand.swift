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

        let skeleton = SpecSkeleton.from(scan: scan)
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

        printSummary(skeleton, createdFiles: createdFiles)
    }

    // MARK: - output

    private func printSummary(_ s: SpecSkeleton, createdFiles: [String]) {
        print("✓ Initialized Relios")
        print("")
        print("Created files:")
        for file in createdFiles {
            print("  \(file)")
        }
        print("")
        print("Detected:")
        print("  project type:  swiftpm")
        print("  binary target: \(s.binaryTarget)")
        print("")
        print("Review before first release:")
        print("  [app].bundle_id      (currently \(s.bundleId))")
        if createdFiles.contains("AppVersion.swift") {
            print("  AppVersion.swift     (generated with 0.1.0 build 1)")
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
