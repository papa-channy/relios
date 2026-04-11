/// Identifies which step of `ReleasePipeline` produced an error.
///
/// v1 dry-run only includes steps that actually run. The full enum from the
/// design doc (15 steps) lands incrementally as the pipeline grows beyond
/// dry-run. Steps that don't exist yet (e.g. `installApp`, `signAdhoc`)
/// are intentionally absent — adding a case here that no one throws is
/// dead code.
public enum ReleaseStep: String, Sendable, Equatable {
    case preflightValidation
    case readCurrentVersion
    case computeNextVersion
    case build
    case verifyBuildArtifact
    case updateVersionSource
    case assembleAppBundle
    case writeInfoPlist
    case signAdhoc
    case backupExistingApp
    case terminateRunningApp
    case installApp
    case launchApp
    case writeReleaseManifest

    public var label: String {
        switch self {
        case .preflightValidation: return "preflight validation"
        case .readCurrentVersion:  return "read current version"
        case .computeNextVersion:  return "compute next version"
        case .build:               return "build"
        case .verifyBuildArtifact: return "verify build artifact"
        case .updateVersionSource: return "update version source"
        case .assembleAppBundle:   return "assemble app bundle"
        case .writeInfoPlist:      return "write Info.plist"
        case .signAdhoc:           return "sign (ad-hoc)"
        case .backupExistingApp:   return "backup existing app"
        case .terminateRunningApp: return "terminate running app"
        case .installApp:          return "install app"
        case .launchApp:           return "launch app"
        case .writeReleaseManifest: return "write release manifest"
        }
    }
}
