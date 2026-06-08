import Foundation
import ReliosSupport

/// Static path-safety checks on the spec, so `doctor` and `release` preflight
/// reject dangerous configurations before any destructive operation runs:
///   - `[bundle].output_path` must resolve inside the project root
///   - `[install].path` must be a `.app`, must not be a protected target
///     (`/`, `$HOME`, project root), and must differ from `output_path`.
public struct PathSafetyRule: ValidationRule {
    private let homeDir: String

    public init(homeDir: String = NSHomeDirectory()) {
        self.homeDir = homeDir
    }

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let root = context.projectRoot
        let outputPath = context.spec.bundle.outputPath
        let installPath = context.spec.install.path

        let resolvedOutput: String
        do {
            resolvedOutput = try PathSafety.resolveWithinRoot(outputPath, root: root)
        } catch {
            return .fail(
                title: "output path escapes project",
                reason: "[bundle].output_path '\(outputPath)' is absolute or escapes the project root",
                fix: "Use a path inside the project, e.g. dist/<App>.app",
                code: DiagnosticCode("PATH_OUTPUT_ESCAPES_ROOT")
            )
        }

        if !PathSafety.normalize(installPath).hasSuffix(".app") {
            return .fail(
                title: "install path is not an .app",
                reason: "[install].path '\(installPath)' must end in .app",
                fix: "Set [install].path to a .app bundle, e.g. /Applications/<App>.app",
                code: DiagnosticCode("PATH_INSTALL_NOT_APP")
            )
        }

        if PathSafety.isDangerousTarget(installPath, projectRoot: root, homeDir: homeDir) {
            return .fail(
                title: "install path is a protected location",
                reason: "[install].path '\(installPath)' resolves to /, your home, or the project root",
                fix: "Point [install].path at a .app under /Applications or a dedicated dir",
                code: DiagnosticCode("PATH_INSTALL_DANGEROUS")
            )
        }

        if PathSafety.normalize(resolvedOutput) == PathSafety.normalize(installPath) {
            return .fail(
                title: "output and install paths are identical",
                reason: "[bundle].output_path and [install].path resolve to the same location",
                fix: "Build to dist/ and install to /Applications (they must differ)",
                code: DiagnosticCode("PATH_OUTPUT_EQUALS_INSTALL")
            )
        }

        return .ok(title: "paths safe", code: DiagnosticCode("PATHS_OK"))
    }
}
