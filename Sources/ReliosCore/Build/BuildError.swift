/// Domain error for `SwiftBuildRunner`.
/// `ReleasePipeline` catches and translates to `ReleaseError.buildFailed`
/// or `ReleaseError.artifactNotFound` depending on which method failed.
public enum BuildError: Error, Equatable {
    case processFailed(command: String, underlying: String)
    case nonZeroExit(command: String, exitCode: Int32, stderrTail: String)
    case binaryNotFound(searched: [String])
}

extension BuildError {
    public var shortReason: String {
        switch self {
        case .processFailed(let cmd, _):
            return "Could not execute build command: \(cmd)"
        case .nonZeroExit(let cmd, let code, _):
            return "Build command exited with code \(code): \(cmd)"
        case .binaryNotFound:
            return "Build artifact not found at the configured path"
        }
    }

    public var shortFix: String {
        switch self {
        case .processFailed:
            return "Verify [build].command can be executed by your shell"
        case .nonZeroExit:
            return "Run with --verbose to see full build output"
        case .binaryNotFound(let searched):
            return "Update [build].binary_path. Searched: " + searched.joined(separator: ", ")
        }
    }

    public var stderrTail: String? {
        if case .nonZeroExit(_, _, let tail) = self { return tail }
        return nil
    }
}
