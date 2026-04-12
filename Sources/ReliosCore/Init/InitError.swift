/// Domain error for `relios init`.
/// Surfaced to the user via `ReliosError` in a later slice — for now,
/// `InitCommand` catches and prints it directly.
public enum InitError: Error, Equatable {
    case notSwiftPMProject(root: String)
    case writeFailed(path: String, underlying: String)
}

extension InitError {
    public var shortReason: String {
        switch self {
        case .notSwiftPMProject(let root):
            return "No Package.swift or Xcode project found at \(root)"
        case .writeFailed(let path, _):
            return "Could not write relios.toml to \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .notSwiftPMProject:
            return "Run `relios init` from the root of a SwiftPM project (Package.swift) or Xcode project (.xcodeproj / .xcworkspace / project.yml)"
        case .writeFailed:
            return "Check directory permissions"
        }
    }
}
