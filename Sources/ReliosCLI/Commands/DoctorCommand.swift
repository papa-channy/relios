import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct DoctorCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose whether the project is ready to release."
    )

    @Flag(name: .long, help: "Apply safe automatic fixes, then re-run the checks.")
    public var fix: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output.")
    public var verbose: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "doctor", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                printSpecLoadFailure(error)
            }
            throw ExitCode.failure
        }

        let process = RealProcessRunner()
        let context = ValidationContext(
            spec: spec,
            projectRoot: root,
            fs: fs,
            process: process
        )

        // --fix applies safe, additive fixes before diagnosing, so the
        // re-run below reflects the post-fix state.
        if fix {
            let fixer = DoctorFixer(fixes: [
                InstallPathFix(),
            ])
            let results = fixer.run(context)
            if !global.isJSON { printFixResults(results) }
        }

        let runner = DoctorRunner(rules: [
            XcodeProjectGuardRule(),
            SpecValidityRule(),
            VersionSourceRule(),
            BuildReadinessRule(),
            InstallPathRule(),
            SigningReadinessRule(),
            DMGReadinessRule(),
            NotarizeReadinessRule(),
            UpdateReadinessRule(),
            PathSafetyRule(),
            BuildTrustRule(),
        ])

        let diagnostics = runner.run(context)

        if global.isJSON {
            Report.checks(command: "doctor", diagnostics: diagnostics)
        } else {
            for diagnostic in diagnostics {
                printDiagnostic(diagnostic)
            }
            printSummary(diagnostics)
        }

        if diagnostics.contains(where: { $0.status == .fail }) {
            throw ExitCode.failure
        }
    }

    // MARK: - output

    private func printFixResults(_ results: [FixResult]) {
        guard !results.isEmpty else {
            print("Nothing to fix.")
            print("")
            return
        }
        for r in results {
            switch r.status {
            case .fixed:
                print("[fixed] \(r.title)")
            case .failed:
                print("[fail] \(r.title)")
            }
            print("  \(r.detail)")
        }
        print("")
    }

    private func printDiagnostic(_ d: Diagnostic) {
        let symbol: String
        switch d.status {
        case .ok:   symbol = "[ok]"
        case .warn: symbol = "[warn]"
        case .fail: symbol = "[fail]"
        }
        print("\(symbol) \(d.title)")
        if let reason = d.reason {
            print("  Reason: \(reason)")
        }
        if let fix = d.fix {
            print("  Fix: \(fix)")
        }
    }

    private func printSummary(_ diagnostics: [Diagnostic]) {
        let failures = diagnostics.filter { $0.status == .fail }.count
        let warnings = diagnostics.filter { $0.status == .warn }.count

        let status: String
        if failures > 0 {
            status = "not ready"
        } else if warnings > 0 {
            status = "mostly ready"
        } else {
            status = "ready"
        }

        print("")
        print("Status: \(status)")
    }

    private func printSpecLoadFailure(_ error: SpecLoadError) {
        print("[fail] spec load")
        print("  Reason: \(error.shortReason)")
        print("  Fix: \(error.shortFix)")
    }
}
