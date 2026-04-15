/// Domain error for `relios ci init`.
public enum CIError: Error, Equatable {
    case specMissing(path: String)
    case workflowExists(paths: [String])
    case writeFailed(path: String, underlying: String)
}

extension CIError {
    public var shortReason: String {
        switch self {
        case .specMissing(let path):
            return "relios.toml not found at \(path)"
        case .workflowExists(let paths):
            if paths.count == 1 {
                return "Workflow already exists at \(paths[0])"
            }
            return "Workflows already exist:\n    " + paths.joined(separator: "\n    ")
        case .writeFailed(let path, _):
            return "Could not write workflow to \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .specMissing:
            return "Run `relios init` first to create relios.toml"
        case .workflowExists:
            return "Re-run with `--force` to overwrite, or delete the files manually"
        case .writeFailed:
            return "Check directory permissions"
        }
    }
}
