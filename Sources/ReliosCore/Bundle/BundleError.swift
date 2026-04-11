/// Domain error for bundle assembly operations.
public enum BundleError: Error, Equatable {
    case binaryUnreadable(path: String, underlying: String)
    case plistWriteFailed(path: String, underlying: String)
}

extension BundleError {
    public var shortReason: String {
        switch self {
        case .binaryUnreadable(let path, _):
            return "Could not read binary at \(path)"
        case .plistWriteFailed(let path, _):
            return "Could not write Info.plist at \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .binaryUnreadable:
            return "Verify [build].binary_path and rebuild"
        case .plistWriteFailed:
            return "Check directory permissions for [bundle].output_path"
        }
    }
}
