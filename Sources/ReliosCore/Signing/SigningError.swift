/// Domain error for `AdhocSigner`.
public enum SigningError: Error, Equatable {
    case processFailed(command: String, underlying: String)
    case nonZeroExit(exitCode: Int32, stderrTail: String)
}

extension SigningError {
    public var shortReason: String {
        switch self {
        case .processFailed(let cmd, _):
            return "Could not run codesign: \(cmd)"
        case .nonZeroExit(let code, _):
            return "codesign exited with code \(code)"
        }
    }

    public var shortFix: String {
        switch self {
        case .processFailed:
            return "Verify `codesign` is available (install Xcode Command Line Tools)"
        case .nonZeroExit:
            return "Run with --verbose to see codesign output"
        }
    }
}
