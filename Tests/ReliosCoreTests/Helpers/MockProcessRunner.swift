import ReliosSupport

/// Test fake for `ProcessRunner`. Records every shell call and returns a
/// canned `ProcessResult` (or pulls successive results from a queue).
final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let command: String
        let cwd: String?
    }

    private(set) var calls: [Call] = []
    private var cannedResults: [ProcessResult]
    private let defaultResult: ProcessResult

    /// Command-pattern overrides: if a command contains the key string,
    /// this result is returned instead of the canned/default. Checked first.
    /// Example: `process.commandOverrides["pgrep"] = ProcessResult(exitCode: 1, ...)`
    var commandOverrides: [String: ProcessResult] = [:]

    /// One static result for every call.
    init(result: ProcessResult) {
        self.cannedResults = []
        self.defaultResult = result
    }

    /// First call returns `results[0]`, second returns `results[1]`, etc.
    /// After the queue is exhausted, falls back to `defaultResult`.
    init(queue results: [ProcessResult], default defaultResult: ProcessResult = .success) {
        self.cannedResults = results
        self.defaultResult = defaultResult
    }

    func runShell(_ command: String, cwd: String?) throws -> ProcessResult {
        calls.append(Call(command: command, cwd: cwd))
        for (pattern, result) in commandOverrides {
            if command.contains(pattern) { return result }
        }
        if cannedResults.isEmpty { return defaultResult }
        return cannedResults.removeFirst()
    }
}

extension ProcessResult {
    static let success = ProcessResult(exitCode: 0, stdout: "", stderr: "")

    static func failure(exitCode: Int32 = 1, stderr: String = "build failed") -> ProcessResult {
        ProcessResult(exitCode: exitCode, stdout: "", stderr: stderr)
    }
}
