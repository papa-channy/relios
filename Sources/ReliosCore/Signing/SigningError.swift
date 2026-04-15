/// Domain error for signing flow (`AdhocSigner`, `DeveloperIDSigner`).
public enum SigningError: Error, Equatable {
    case processFailed(command: String, underlying: String)
    case nonZeroExit(exitCode: Int32, stderrTail: String)
    /// Developer ID mode requires `identity` and `team_id` to be set.
    /// Preflight validation normally catches this; this case exists so
    /// the pipeline can fail loudly if the validator is ever bypassed.
    case missingDeveloperIDConfig(field: String)
}

extension SigningError {
    public var shortReason: String {
        switch self {
        case .processFailed(let cmd, _):
            return "Could not run codesign: \(cmd)"
        case .nonZeroExit(let code, _):
            return "codesign exited with code \(code)"
        case .missingDeveloperIDConfig(let field):
            return "signing.\(field) is required when mode = \"developer-id\""
        }
    }

    public var shortFix: String {
        switch self {
        case .processFailed:
            return "Verify `codesign` is available (install Xcode Command Line Tools)"
        case .nonZeroExit:
            return "Run with --verbose to see codesign output"
        case .missingDeveloperIDConfig:
            return "Run `relios signing setup` to populate [signing] in relios.toml"
        }
    }
}
