import Foundation

/// Boundary protocol for filesystem operations.
/// Production code uses `RealFileSystem`; tests inject in-memory fakes.
///
/// Reads (`fileExists`, `isDirectory`, `listDirectory`, `readUTF8`) are
/// non-mutating; `writeUTF8` is the only mutating boundary in v1.
public protocol FileSystem: Sendable {
    func fileExists(at path: String) -> Bool
    func isDirectory(at path: String) -> Bool
    func listDirectory(at path: String) throws -> [String]
    func readUTF8(at path: String) throws -> String
    func writeUTF8(_ content: String, to path: String) throws
    /// Copy a file (binary or text) from `source` to `destination`,
    /// creating parent directories as needed. Used for copying executables
    /// and resource bundles into `.app` bundles.
    func copyFile(from source: String, to destination: String) throws
    func removeItem(at path: String) throws
    func moveItem(from source: String, to destination: String) throws
    func createDirectory(at path: String) throws
    /// Resolve symlinks and `..`/`.` to a canonical absolute path. Used for
    /// real-filesystem escape detection. Returns `nil` if it can't be resolved.
    func canonicalize(_ path: String) -> String?
    /// Whether `path` is itself a symbolic link (not whether its target is).
    func isSymlink(at path: String) -> Bool
    /// Read raw bytes (for hashing binary artifacts). Distinct from `readUTF8`
    /// which assumes text.
    func readData(at path: String) throws -> Data
}

extension FileSystem {
    /// Default: lexical normalization only (no symlink resolution). Fakes used
    /// in tests inherit this; `RealFileSystem` overrides with real `realpath`.
    public func canonicalize(_ path: String) -> String? {
        PathSafety.normalize(path)
    }
    /// Default: fakes have no symlinks.
    public func isSymlink(at path: String) -> Bool { false }
    /// Default: treat stored text as its UTF-8 bytes (works for in-memory fakes).
    public func readData(at path: String) throws -> Data {
        Data(try readUTF8(at: path).utf8)
    }
}

public struct RealFileSystem: FileSystem {
    public init() {}

    public func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(at path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    public func listDirectory(at path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    public func readUTF8(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public func writeUTF8(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func copyFile(from source: String, to destination: String) throws {
        let destURL = URL(fileURLWithPath: destination)
        let destDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination) {
            try FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }

    public func removeItem(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    public func moveItem(from source: String, to destination: String) throws {
        let destURL = URL(fileURLWithPath: destination)
        let destDir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination) {
            try FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.moveItem(atPath: source, toPath: destination)
    }

    public func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func canonicalize(_ path: String) -> String? {
        // realpath resolves symlinks + `..` for the existing portion of the
        // path. For a not-yet-existing leaf, resolve the deepest existing
        // ancestor and re-append the remainder.
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath().path
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) {
            return parent.resolvingSymlinksInPath()
                .appendingPathComponent(url.lastPathComponent).path
        }
        return url.path
    }

    public func isSymlink(at path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    public func readData(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
