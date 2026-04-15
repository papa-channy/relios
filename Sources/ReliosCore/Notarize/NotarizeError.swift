/// Domain error for `relios notarize`.
public enum NotarizeError: Error, Equatable {
    case disabled
    case artifactMissing(path: String)
    case unsupportedArtifact(path: String)
    case missingCredentials(envVars: [String])
    case teamIDMismatch(signing: String, notarize: String)
    case notarytoolNotFound
    case submissionFailed(exitCode: Int32, log: String)
    case stapleFailed(exitCode: Int32, stderr: String)
    case repackFailed(underlying: String)
}

extension NotarizeError {
    public var shortReason: String {
        switch self {
        case .disabled:
            return "Notarization is disabled"
        case .artifactMissing(let path):
            return "Artifact not found at \(path)"
        case .unsupportedArtifact(let path):
            return "Cannot notarize \(path) — must be .zip or .dmg"
        case .missingCredentials(let vars):
            return "Missing env vars: \(vars.joined(separator: ", "))"
        case .teamIDMismatch(let signing, let notarize):
            return "team_id mismatch: signing=\(signing) vs APPLE_TEAM_ID=\(notarize)"
        case .notarytoolNotFound:
            return "`xcrun notarytool` is not available"
        case .submissionFailed(let code, let log):
            return "notarytool submit exited \(code):\n\(log)"
        case .stapleFailed(let code, let stderr):
            return "stapler staple exited \(code): \(stderr)"
        case .repackFailed(let u):
            return "Could not re-zip stapled .app: \(u)"
        }
    }

    public var shortFix: String {
        switch self {
        case .disabled:
            return "Set `[notarize].enabled = true` in relios.toml"
        case .artifactMissing:
            return "Run `relios release` (and `relios dmg` if applicable) first"
        case .unsupportedArtifact:
            return "Pass a .zip or .dmg path, or omit to auto-detect"
        case .missingCredentials(let vars):
            return "Set: " + vars.map { "export \($0)='...'" }.joined(separator: "; ")
        case .teamIDMismatch:
            return "Ensure APPLE_TEAM_ID (env) matches [signing].team_id (relios.toml)"
        case .notarytoolNotFound:
            return "Install Xcode 13+ (Command Line Tools alone don't include notarytool)"
        case .submissionFailed:
            return "Re-run `xcrun notarytool log <submission-id>` for details"
        case .stapleFailed:
            return "Check that the artifact is signed with a valid Developer ID cert"
        case .repackFailed:
            return "Ensure the workspace has write access to the artifact directory"
        }
    }
}
