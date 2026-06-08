import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

/// Clears a stale project lock and resolves leftover state (scratch dirs,
/// stashed apps) from a hard-killed run. Safe and idempotent.
public struct RecoverCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Clear a stale lock and resolve leftover state from an interrupted run."
    )

    @Flag(name: .long, help: "Show what would be done without changing anything.")
    public var dryRun: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    struct RecoverPayload: Encodable {
        let dryRun: Bool
        let findings: [RecoverRunner.Finding]
        enum CodingKeys: String, CodingKey {
            case dryRun = "dry_run"
            case findings
        }
    }

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: root + "/relios.toml")
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "recover", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[recover] failed at: spec load")
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
        let findings = runner.recover(spec: spec, projectRoot: root, dryRun: dryRun)

        if global.isJSON {
            Report.success(command: "recover", data: RecoverPayload(dryRun: dryRun, findings: findings))
            return
        }

        let verb = dryRun ? "Would resolve" : "Resolved"
        if findings.isEmpty {
            print("Nothing to recover — state is clean.")
        } else {
            print("\(verb):")
            for f in findings {
                print("  [\(f.action.rawValue)] \(f.path)")
            }
        }
    }
}
