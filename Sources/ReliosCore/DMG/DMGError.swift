/// Domain error for `relios dmg`.
public enum DMGError: Error, Equatable {
    case disabled
    case appMissing(path: String)
    case dmgbuildNotFound
    case dmgbuildFailed(exitCode: Int32, stderr: String)
    case writeFailed(path: String, underlying: String)
}

extension DMGError {
    public var shortReason: String {
        switch self {
        case .disabled:
            return "DMG generation is disabled"
        case .appMissing(let path):
            return ".app bundle not found at \(path)"
        case .dmgbuildNotFound:
            return "`dmgbuild` is not available on PATH"
        case .dmgbuildFailed(let code, let stderr):
            return "dmgbuild exited with code \(code): \(stderr.isEmpty ? "(no stderr)" : stderr)"
        case .writeFailed(let path, _):
            return "Could not write to \(path)"
        }
    }

    public var shortFix: String {
        switch self {
        case .disabled:
            return "Set `[dmg].enabled = true` in relios.toml (or omit the section entirely to keep DMG off)"
        case .appMissing:
            return "Run `relios release` first to produce the .app bundle"
        case .dmgbuildNotFound:
            return "Install it: `pip install dmgbuild` (or `pipx install dmgbuild`)"
        case .dmgbuildFailed:
            return "Re-run with `--verbose` to see dmgbuild's full output"
        case .writeFailed:
            return "Check directory permissions"
        }
    }
}
