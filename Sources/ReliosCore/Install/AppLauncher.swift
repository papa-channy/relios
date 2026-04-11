import ReliosSupport

/// Launches an installed .app via `/usr/bin/open`.
public struct AppLauncher: Sendable {
    private let process: any ProcessRunner

    public init(process: any ProcessRunner) {
        self.process = process
    }

    public func launch(appPath: String) throws {
        let result = try process.runShell("/usr/bin/open '\(appPath)'", cwd: nil)
        guard result.exitCode == 0 else {
            throw InstallError.launchFailed(
                reason: "open exited with code \(result.exitCode): \(result.stderr)"
            )
        }
    }
}
