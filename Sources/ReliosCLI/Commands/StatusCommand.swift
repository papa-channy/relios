import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

/// Read-only: shows the project lock holder and any leftover state from an
/// interrupted run, plus what `relios recover` would do about it.
public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the project lock and any leftover state from an interrupted run."
    )

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: root + "/relios.toml")
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "status", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[status] failed at: spec load")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        let runner = RecoverRunner(
            fs: fs,
            pid: ProcessInfo.processInfo.processIdentifier,
            hostname: ProcessInfo.processInfo.hostName
        )
        let report = runner.scan(spec: spec, projectRoot: root)

        if global.isJSON {
            Report.success(command: "status", data: report)
            return
        }

        if let holder = report.lockHolder {
            let staleNote = report.lockStale ? " (STALE — holder not running)" : ""
            print("Lock: held by `\(holder.command)` pid \(holder.pid) on \(holder.hostname)\(staleNote)")
        } else {
            print("Lock: none")
        }
        if report.findings.isEmpty {
            print("State: clean")
        } else {
            print("Leftover state (run `relios recover` to resolve):")
            for f in report.findings {
                print("  [\(f.action.rawValue)] \(f.path)")
            }
        }
    }
}
