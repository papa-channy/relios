import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct InstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the most recently built .app bundle without rebuilding."
    )

    @Option(name: .long, help: "Override [install].path from relios.toml.")
    public var installPath: String?

    @Flag(name: .long, help: "Do not auto-launch after install.")
    public var noOpen: Bool = false

    @Flag(name: .long, help: "Skip backup of the currently installed app.")
    public var skipBackup: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let lock = try acquireProjectLock(command: "install", projectRoot: root, json: global.isJSON)
        defer { lock.release(projectRoot: root) }
        let fs = RealFileSystem()
        let process = RealProcessRunner()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "install", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[install] failed at: spec load")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        let runner = InstallRunner(fs: fs, process: process)
        let result: InstallRunner.Result
        do {
            result = try runner.run(
                spec: spec,
                projectRoot: root,
                installPathOverride: installPath,
                skipBackup: skipBackup,
                noOpen: noOpen
            )
        } catch let error as InstallError {
            if global.isJSON {
                Report.failure(command: "install", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[install] failed")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "install", data: result)
            return
        }

        printResult(result, appName: spec.app.name)
    }

    // MARK: - output

    private func printResult(_ r: InstallRunner.Result, appName: String) {
        print("✓ Version: \(r.version) (build \(r.build))")
        if r.backupPath != nil {
            print("✓ Backed up previous app")
        }
        print("✓ Installed to \(r.installedAt)")
        if r.launched {
            print("✓ Launched \(appName)")
        }

        print("")
        print("  Bundle:  \(r.bundlePath)")
        print("  Install: \(r.installedAt)")
        if let backup = r.backupPath {
            print("  Backup:  \(backup)")
        }
    }
}
