import ReliosSupport

/// Terminates a running app using a 3-step fallback:
///   1. bundle id (`osascript -e 'tell application id "..." to quit'`)
///   2. installed app path (`pkill -f <path>`)
///   3. executable name (`pkill -x <name>`)
///
/// Returns which method succeeded, or `.wasNotRunning` if the app wasn't found.
/// Each method waits briefly then escalates to SIGKILL if the process persists.
public struct RunningAppTerminator: Sendable {
    public enum Outcome: Sendable, Equatable {
        case wasNotRunning
        case terminated(method: String)
    }

    private let process: any ProcessRunner

    public init(process: any ProcessRunner) {
        self.process = process
    }

    public func terminate(
        bundleId: String,
        installedAppPath: String,
        executableName: String
    ) throws -> Outcome {
        // 1. Try osascript (graceful quit via bundle id)
        let osascript = "osascript -e 'tell application id \"\(bundleId)\" to quit' 2>/dev/null; sleep 1"
        let r1 = try process.runShell(osascript, cwd: nil)
        // Check if it's gone
        let check1 = try process.runShell("pgrep -f '\(installedAppPath)' > /dev/null 2>&1", cwd: nil)
        if check1.exitCode != 0 {
            // Process not found → either quit or was never running
            return r1.exitCode == 0 ? .terminated(method: "bundleId") : .wasNotRunning
        }

        // 2. Try pkill -f (by path)
        _ = try process.runShell("pkill -f '\(installedAppPath)' 2>/dev/null; sleep 1", cwd: nil)
        let check2 = try process.runShell("pgrep -f '\(installedAppPath)' > /dev/null 2>&1", cwd: nil)
        if check2.exitCode != 0 {
            return .terminated(method: "installedPath")
        }

        // 3. Try pkill -x (by name) + SIGKILL fallback
        _ = try process.runShell("pkill -x '\(executableName)' 2>/dev/null; sleep 1", cwd: nil)
        let check3 = try process.runShell("pgrep -x '\(executableName)' > /dev/null 2>&1", cwd: nil)
        if check3.exitCode != 0 {
            return .terminated(method: "executableName")
        }

        // Last resort: SIGKILL
        _ = try process.runShell("pkill -9 -x '\(executableName)' 2>/dev/null; sleep 1", cwd: nil)
        let check4 = try process.runShell("pgrep -x '\(executableName)' > /dev/null 2>&1", cwd: nil)
        if check4.exitCode != 0 {
            return .terminated(method: "executableName (SIGKILL)")
        }

        throw InstallError.terminateFailed(
            reason: "Could not terminate \(executableName) after all fallback methods"
        )
    }
}
