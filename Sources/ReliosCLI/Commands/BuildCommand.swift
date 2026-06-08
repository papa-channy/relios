import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct BuildCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Run the release build defined in [build].command without installing."
    )

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let process = RealProcessRunner()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "build", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[build] failed at: spec load")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        let runner = BuildOnlyRunner(process: process, fs: fs)
        let result: BuildOnlyRunner.Result
        do {
            result = try runner.run(spec: spec, projectRoot: root)
        } catch let error as BuildError {
            if global.isJSON {
                Report.failure(command: "build", code: error.code,
                               reason: error.shortReason, fix: error.shortFix,
                               detail: verbose ? error.stderrTail : nil)
            } else {
                print("[build] failed")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
                if verbose, let tail = error.stderrTail, !tail.isEmpty {
                    print("")
                    print("--- stderr (tail) ---")
                    print(tail)
                }
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "build", data: result)
            return
        }

        print("✓ Build completed")
        if result.passthrough {
            print("✓ Verified .app exists")
        } else {
            print("✓ Verified build artifact")
        }
        print("")
        print("  Artifact: \(result.artifactPath)")
    }
}
