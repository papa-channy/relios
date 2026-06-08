import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct OpenCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Launch the currently installed app."
    )

    @Option(name: .long, help: "Override [install].path from relios.toml.")
    public var installPath: String?

    @OptionGroup public var global: GlobalOptions

    public init() {}

    struct OpenPayload: Encodable {
        let app: String
        let path: String
    }

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
                Report.failure(command: "open", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[open] failed at: spec load")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        let appPath = installPath ?? spec.install.path

        guard fs.isDirectory(at: appPath) else {
            if global.isJSON {
                Report.failure(command: "open", code: DiagnosticCode("INSTALL_APP_NOT_FOUND"),
                               reason: "No installed app at \(appPath)",
                               fix: "Run `relios release` or `relios install` first")
            } else {
                print("[open] failed")
                print("  Reason: No installed app at \(appPath)")
                print("  Fix: Run `relios release` or `relios install` first")
            }
            throw ExitCode.failure
        }

        let launcher = AppLauncher(process: process)
        do {
            try launcher.launch(appPath: appPath)
        } catch let error as InstallError {
            if global.isJSON {
                Report.failure(command: "open", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[open] failed")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "open", data: OpenPayload(app: spec.app.name, path: appPath))
            return
        }

        print("✓ Launched \(spec.app.name)")
    }
}
