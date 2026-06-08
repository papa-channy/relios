/// Surface error thrown by `ReleasePipeline`.
///
/// Each case carries the user-visible `reason` and `fix` strings, along with
/// a `step` so `ConsoleReporter` can print "Release failed at: <step>".
/// Domain errors (`BuildError`, `VersionSourceError`) are caught inside the
/// pipeline and translated into the right case here — that way the CLI
/// only ever has to switch on `ReleaseError`, never on five different
/// domain enums.
public enum ReleaseError: Error, Equatable {
    case preflightFailed(ruleTitle: String, reason: String, fix: String, code: DiagnosticCode)
    case versionReadFailed(reason: String, fix: String)
    case buildFailed(reason: String, fix: String, stderrTail: String?)
    case artifactNotFound(searched: [String])
    case versionUpdateFailed(reason: String, fix: String)
    case bundleAssemblyFailed(reason: String, fix: String)
    case plistWriteFailed(reason: String, fix: String)
    case signingFailed(reason: String, fix: String, stderrTail: String?)
    case backupFailed(reason: String, fix: String)
    case terminateFailed(reason: String, fix: String)
    case installFailed(reason: String, fix: String)
    case launchFailed(reason: String, fix: String)
    case manifestWriteFailed(reason: String, fix: String)
}

extension ReleaseError {
    public var step: ReleaseStep {
        switch self {
        case .preflightFailed:      return .preflightValidation
        case .versionReadFailed:    return .readCurrentVersion
        case .buildFailed:          return .build
        case .artifactNotFound:     return .verifyBuildArtifact
        case .versionUpdateFailed:  return .updateVersionSource
        case .bundleAssemblyFailed: return .assembleAppBundle
        case .plistWriteFailed:     return .writeInfoPlist
        case .signingFailed:        return .signAdhoc
        case .backupFailed:         return .backupExistingApp
        case .terminateFailed:      return .terminateRunningApp
        case .installFailed:        return .installApp
        case .launchFailed:         return .launchApp
        case .manifestWriteFailed:  return .writeReleaseManifest
        }
    }

    /// Stable machine-readable identifier for JSON output. `preflightFailed`
    /// carries the failing rule's own code so the release error surfaces the
    /// specific cause (e.g. SIGNING_IDENTITY_NOT_FOUND), not a generic one.
    public var code: DiagnosticCode {
        switch self {
        case .preflightFailed(_, _, _, let code): return code
        case .versionReadFailed:    return DiagnosticCode("VERSION_SOURCE_READ_FAILED")
        case .buildFailed:          return DiagnosticCode("BUILD_FAILED")
        case .artifactNotFound:     return DiagnosticCode("BUILD_ARTIFACT_NOT_FOUND")
        case .versionUpdateFailed:  return DiagnosticCode("VERSION_UPDATE_FAILED")
        case .bundleAssemblyFailed: return DiagnosticCode("BUNDLE_ASSEMBLY_FAILED")
        case .plistWriteFailed:     return DiagnosticCode("PLIST_WRITE_FAILED")
        case .signingFailed:        return DiagnosticCode("SIGNING_FAILED")
        case .backupFailed:         return DiagnosticCode("BACKUP_FAILED")
        case .terminateFailed:      return DiagnosticCode("TERMINATE_FAILED")
        case .installFailed:        return DiagnosticCode("INSTALL_FAILED")
        case .launchFailed:         return DiagnosticCode("LAUNCH_FAILED")
        case .manifestWriteFailed:  return DiagnosticCode("MANIFEST_WRITE_FAILED")
        }
    }

    public var reason: String {
        switch self {
        case .preflightFailed(let title, let reason, _, _):
            return "\(title): \(reason)"
        case .versionReadFailed(let reason, _),
             .versionUpdateFailed(let reason, _),
             .bundleAssemblyFailed(let reason, _),
             .plistWriteFailed(let reason, _),
             .buildFailed(let reason, _, _),
             .signingFailed(let reason, _, _),
             .backupFailed(let reason, _),
             .terminateFailed(let reason, _),
             .installFailed(let reason, _),
             .launchFailed(let reason, _),
             .manifestWriteFailed(let reason, _):
            return reason
        case .artifactNotFound:
            return "Build artifact not found at the configured path"
        }
    }

    public var fix: String {
        switch self {
        case .preflightFailed(_, _, let fix, _):
            return fix
        case .versionReadFailed(_, let fix),
             .versionUpdateFailed(_, let fix),
             .bundleAssemblyFailed(_, let fix),
             .plistWriteFailed(_, let fix),
             .buildFailed(_, let fix, _),
             .signingFailed(_, let fix, _),
             .backupFailed(_, let fix),
             .terminateFailed(_, let fix),
             .installFailed(_, let fix),
             .launchFailed(_, let fix),
             .manifestWriteFailed(_, let fix):
            return fix
        case .artifactNotFound(let searched):
            return "Update [build].binary_path. Searched: " + searched.joined(separator: ", ")
        }
    }

    public var stderrTail: String? {
        switch self {
        case .buildFailed(_, _, let tail), .signingFailed(_, _, let tail):
            return tail
        default:
            return nil
        }
    }
}
