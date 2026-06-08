import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct RollbackCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "rollback",
        abstract: "Restore the previous installed app from the most recent backup."
    )

    @Option(name: .long, help: "Specific backup zip to restore. Defaults to the latest backup.")
    public var to: String?

    @Flag(name: .long, help: "Do not auto-launch after restore.")
    public var noOpen: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let lock = try acquireProjectLock(command: "rollback", projectRoot: root, json: global.isJSON)
        defer { lock.release(projectRoot: root) }
        let fs = RealFileSystem()
        let process = RealProcessRunner()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "rollback", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[rollback] failed: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        let runner = RollbackRunner(fs: fs, process: process)
        let result: RollbackRunner.Result
        do {
            result = try runner.run(
                spec: spec,
                projectRoot: root,
                specificBackup: to,
                noOpen: noOpen
            )
        } catch let error as RollbackError {
            if global.isJSON {
                Report.failure(command: "rollback", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[rollback] failed: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "rollback", data: result)
            return
        }

        print("✓ Restored from: \(result.restoredFrom)")
        print("✓ Installed at:  \(result.installedAt)")
        if result.launched {
            print("✓ Launched app")
        }
    }
}
