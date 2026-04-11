import Foundation

/// Boundary protocol for spawning subprocesses.
/// Production code uses `RealProcessRunner`; tests inject `MockProcessRunner`.
///
/// v1 only exposes a single shell-style entrypoint because every command we
/// run (`swift build -c release`, `codesign`, `ditto`, ...) is naturally a
/// shell-quoted string in `relios.toml` or hard-coded. The shell handles
/// PATH lookup and arg splitting; we don't try to outsmart it.
public protocol ProcessRunner: Sendable {
    /// Run `command` via `/bin/sh -c`. Optionally chdir to `cwd` first.
    /// Returns whatever the subprocess produced; does NOT throw on non-zero
    /// exit (callers decide what counts as failure).
    func runShell(_ command: String, cwd: String?) throws -> ProcessResult
}

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct RealProcessRunner: ProcessRunner {
    public init() {}

    public func runShell(_ command: String, cwd: String?) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
