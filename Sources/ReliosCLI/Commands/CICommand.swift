import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct CICommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ci",
        abstract: "Scaffold GitHub Actions release workflows for this project.",
        subcommands: [InitSubcommand.self, DoctorSubcommand.self],
        defaultSubcommand: InitSubcommand.self
    )

    public init() {}

    public struct InitSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Generate .github/workflows/release.yml from relios.toml."
        )

        @Flag(name: .long, help: "Overwrite an existing workflow file.")
        public var force: Bool = false

        public init() {}

        public func run() throws {
            let root = FileManager.default.currentDirectoryPath
            let runner = CIInitRunner(fs: RealFileSystem())

            let result: CIInitRunner.Result
            do {
                result = try runner.run(projectRoot: root, force: force)
            } catch let error as CIError {
                printFailure(error)
                throw ExitCode.failure
            }

            printSummary(result)
        }

        private func printSummary(_ r: CIInitRunner.Result) {
            for file in r.files {
                let verb = file.overwritten ? "Overwrote" : "Created"
                print("✓ \(verb) \(relativePath(file.path))")
            }
            print("")
            print("Project type: \(r.projectType.rawValue)")
            print("Bundle mode:  \(r.mode.rawValue)")
            print("")
            print("Next steps:")
            print("  1. Commit the workflows:")
            print("       git add .github/workflows && git commit")
            print("  2. Push to trigger CI, or a tag to trigger a release:")
            print("       git tag v0.1.0 && git push origin v0.1.0")
            print("")
            print("Scope: build + test + zip (+ optional DMG) + upload. No Developer ID")
            print("signing or notarization yet — those arrive in a later phase.")
        }

        private func printFailure(_ error: CIError) {
            print("[ci init] failed")
            print("  Reason: \(error.shortReason)")
            print("  Fix: \(error.shortFix)")
        }

        private func relativePath(_ abs: String) -> String {
            let cwd = FileManager.default.currentDirectoryPath + "/"
            if abs.hasPrefix(cwd) {
                return String(abs.dropFirst(cwd.count))
            }
            return abs
        }
    }

    public struct DoctorSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Check that the project is wired up for a GitHub Actions release."
        )

        public init() {}

        public func run() throws {
            let root = FileManager.default.currentDirectoryPath
            let fs = RealFileSystem()
            let specPath = root + "/relios.toml"

            let spec: ReleaseSpec
            do {
                spec = try SpecLoader(fs: fs).load(from: specPath)
            } catch let error as SpecLoadError {
                print("[fail] spec load")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
                throw ExitCode.failure
            }

            let context = ValidationContext(
                spec: spec,
                projectRoot: root,
                fs: fs,
                process: RealProcessRunner()
            )

            let runner = DoctorRunner(rules: [
                ReleaseWorkflowPresenceRule(),
                CIWorkflowPresenceRule(),
                GitHubRemoteRule(),
            ])

            let diagnostics = runner.run(context)
            for d in diagnostics { printDiagnostic(d) }
            printSummary(diagnostics)

            if diagnostics.contains(where: { $0.status == .fail }) {
                throw ExitCode.failure
            }
        }

        private func printDiagnostic(_ d: Diagnostic) {
            let symbol: String
            switch d.status {
            case .ok:   symbol = "[ok]"
            case .warn: symbol = "[warn]"
            case .fail: symbol = "[fail]"
            }
            print("\(symbol) \(d.title)")
            if let reason = d.reason { print("  Reason: \(reason)") }
            if let fix    = d.fix    { print("  Fix: \(fix)") }
        }

        private func printSummary(_ diagnostics: [Diagnostic]) {
            let failures = diagnostics.filter { $0.status == .fail }.count
            let warnings = diagnostics.filter { $0.status == .warn }.count
            let status: String
            if failures > 0 { status = "not ready" }
            else if warnings > 0 { status = "mostly ready" }
            else { status = "ready" }
            print("")
            print("Status: \(status)")
        }
    }
}
