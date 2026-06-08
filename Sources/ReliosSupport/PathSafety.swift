import Foundation

/// Pure, filesystem-free path validation. Used to stop destructive operations
/// from escaping the project (zip-slip on extraction, `..`/absolute escapes in
/// spec paths, and wholesale deletion of dangerous targets like `/` or `$HOME`).
///
/// These are *lexical* checks (no symlink resolution). For real-filesystem
/// symlink-escape detection, combine with `FileSystem.canonicalize`/`isSymlink`.
public enum PathSafety {
    public enum Violation: Error, Equatable {
        case escapesRoot(path: String, root: String)
        case dangerousTarget(path: String)
        case identicalPaths(path: String)
        case nestedPaths(outer: String, inner: String)
        case notAppBundle(path: String)
    }

    /// Lexically normalize: collapse `//`, drop `.`, resolve `..` segments.
    /// Preserves a leading `/` (absolute) and a trailing-slash-free result.
    public static func normalize(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            let s = String(segment)
            if s == "." { continue }
            if s == ".." {
                if let last = stack.last, last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    stack.append("..")  // relative path may climb above its base
                }
                // absolute path: ".." at root stays at root (drop it)
                continue
            }
            stack.append(s)
        }
        let joined = stack.joined(separator: "/")
        if isAbsolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    /// True if `path` is lexically inside `root` (or equal to it).
    public static func isWithin(_ path: String, root: String) -> Bool {
        let np = normalize(path)
        let nr = normalize(root)
        if np == nr { return true }
        return np.hasPrefix(nr.hasSuffix("/") ? nr : nr + "/")
    }

    /// Resolve a spec-relative path under `root`. Returns the normalized absolute
    /// path if it stays within `root`; throws `escapesRoot` for an absolute path
    /// or one that climbs out via `..`.
    public static func resolveWithinRoot(_ relative: String, root: String) throws -> String {
        if relative.hasPrefix("/") {
            throw Violation.escapesRoot(path: relative, root: root)
        }
        let joined = normalize(root + "/" + relative)
        guard isWithin(joined, root: root) else {
            throw Violation.escapesRoot(path: relative, root: root)
        }
        return joined
    }

    /// Paths that must never be the target of a wholesale remove/replace:
    /// filesystem root, the user's home, or the project root itself.
    public static func isDangerousTarget(_ path: String, projectRoot: String, homeDir: String) -> Bool {
        let n = normalize(path)
        if n == "/" || n.isEmpty || n == "." { return true }
        if n == normalize(homeDir) { return true }
        if n == normalize(projectRoot) { return true }
        return false
    }

    /// Guard for a destructive op against a single target.
    public static func assertSafeDestructiveTarget(
        _ path: String, projectRoot: String, homeDir: String
    ) throws {
        if isDangerousTarget(path, projectRoot: projectRoot, homeDir: homeDir) {
            throw Violation.dangerousTarget(path: path)
        }
    }

    /// An install target must be a `.app` bundle.
    public static func assertAppBundle(_ path: String) throws {
        if !normalize(path).hasSuffix(".app") {
            throw Violation.notAppBundle(path: path)
        }
    }

    /// Two paths must not be the same location.
    public static func assertDistinct(_ a: String, _ b: String) throws {
        if normalize(a) == normalize(b) {
            throw Violation.identicalPaths(path: normalize(a))
        }
    }

    /// Neither path may contain the other (would make a copy/remove recursive).
    public static func assertNotNested(_ a: String, _ b: String) throws {
        let na = normalize(a), nb = normalize(b)
        guard na != nb else { return }
        if isWithin(na, root: nb) || isWithin(nb, root: na) {
            throw Violation.nestedPaths(outer: na, inner: nb)
        }
    }

    /// Validate that every extracted entry stays within `targetDir` (zip-slip).
    /// `entries` are paths (absolute or relative to targetDir) discovered after
    /// extraction; any that resolves outside `targetDir` is rejected.
    public static func assertExtractionWithin(_ entries: [String], targetDir: String) throws {
        for entry in entries {
            let resolved = entry.hasPrefix("/") ? normalize(entry) : normalize(targetDir + "/" + entry)
            guard isWithin(resolved, root: targetDir) else {
                throw Violation.escapesRoot(path: entry, root: targetDir)
            }
        }
    }
}
