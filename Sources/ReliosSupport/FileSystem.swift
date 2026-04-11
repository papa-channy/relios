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
}
