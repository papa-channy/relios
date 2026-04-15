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

    /// Like `runShell`, but also tees stdout/stderr to the parent's
    /// stdout/stderr as they arrive. Used for long-running commands
    /// (notarytool submit, brew install, etc.) so CI logs show progress
    /// instead of a silent wait. Returned `ProcessResult` still contains
    /// the full output for downstream parsing.
    func runShellStreaming(_ command: String, cwd: String?) throws -> ProcessResult
}

extension ProcessRunner {
    // Default falls back to buffered mode — keeps existing mocks and
    // non-streaming callers happy.
    public func runShellStreaming(_ command: String, cwd: String?) throws -> ProcessResult {
        try runShell(command, cwd: cwd)
    }
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

    /// Streaming variant: tees each stdout/stderr chunk to the parent's
    /// FileHandle.standardOutput/Error as it arrives, while buffering a
    /// copy for the returned `ProcessResult` so callers can still parse
    /// the full output after completion.
    public func runShellStreaming(_ command: String, cwd: String?) throws -> ProcessResult {
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

        // Reference-type accumulators so the Sendable @concurrent pipe
        // callbacks can mutate them under a lock. Plain `var Data` would
        // hit Swift 6's SendableClosureCaptures diagnostic.
        let stdoutBuffer = LockedBuffer()
        let stderrBuffer = LockedBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardOutput.write(data)
            stdoutBuffer.append(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            FileHandle.standardError.write(data)
            stderrBuffer.append(data)
        }

        try process.run()
        process.waitUntilExit()

        // Detach handlers so the final reads don't double-write.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? "",
            stderr: String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
        )
    }
}

/// Thread-safe `Data` accumulator used by `runShellStreaming`. Reference
/// type so Sendable closures can mutate under a lock without hitting
/// SendableClosureCaptures.
private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }
    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}
