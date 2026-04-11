import Foundation
import ReliosSupport

/// In-memory `FileSystem` fake. Lives in tests, never in production code.
///
/// Backed by a class so `writeUTF8` can mutate from `let fs: any FileSystem`
/// references; marked `@unchecked Sendable` because tests are single-threaded.
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case noFile(String)
        case noDirectory(String)
    }

    private(set) var files: [String: String]
    private(set) var directories: Set<String>

    /// Paths passed to `writeUTF8` since init. Stays empty if no caller wrote.
    /// Used by `ReleasePipelineTests` to lock the dry-run "no writes" invariant.
    private(set) var writeLog: [String] = []

    init(files: [String: String] = [:], directories: Set<String> = []) {
        self.files = files
        var dirs = directories
        // Auto-register every parent directory of every seeded file.
        for path in files.keys {
            Self.registerParents(of: path, into: &dirs)
        }
        // Also register every explicitly-seeded directory's parents.
        for path in directories {
            Self.registerParents(of: path, into: &dirs)
        }
        self.directories = dirs
    }

    func fileExists(at path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func isDirectory(at path: String) -> Bool {
        directories.contains(path)
    }

    func listDirectory(at path: String) throws -> [String] {
        guard directories.contains(path) else {
            throw Failure.noDirectory(path)
        }
        let prefix = path.hasSuffix("/") ? path : path + "/"

        func immediateChild(of fullPath: String) -> String? {
            guard fullPath.hasPrefix(prefix) else { return nil }
            let rest = String(fullPath.dropFirst(prefix.count))
            guard !rest.isEmpty else { return nil }
            if let slashIdx = rest.firstIndex(of: "/") {
                return String(rest[..<slashIdx])
            }
            return rest
        }

        var children = Set<String>()
        for filePath in files.keys {
            if let c = immediateChild(of: filePath) { children.insert(c) }
        }
        for dirPath in directories where dirPath != path {
            if let c = immediateChild(of: dirPath) { children.insert(c) }
        }
        return children.sorted()
    }

    func readUTF8(at path: String) throws -> String {
        guard let content = files[path] else {
            throw Failure.noFile(path)
        }
        return content
    }

    func writeUTF8(_ content: String, to path: String) throws {
        files[path] = content
        writeLog.append(path)
        Self.registerParents(of: path, into: &directories)
    }

    func copyFile(from source: String, to destination: String) throws {
        // Single file copy
        if let content = files[source], !directories.contains(source) {
            files[destination] = content
            writeLog.append(destination)
            Self.registerParents(of: destination, into: &directories)
            return
        }

        // Directory copy: relocate all children under source prefix → destination prefix
        if directories.contains(source) {
            let srcPrefix = source + "/"
            let dstPrefix = destination + "/"
            directories.insert(destination)
            Self.registerParents(of: destination, into: &directories)
            for (path, content) in files where path.hasPrefix(srcPrefix) {
                let relative = String(path.dropFirst(srcPrefix.count))
                let newPath = dstPrefix + relative
                files[newPath] = content
                writeLog.append(newPath)
                Self.registerParents(of: newPath, into: &directories)
            }
            for dir in directories where dir.hasPrefix(srcPrefix) {
                let relative = String(dir.dropFirst(srcPrefix.count))
                directories.insert(dstPrefix + relative)
            }
            return
        }

        throw Failure.noFile(source)
    }

    func removeItem(at path: String) throws {
        if files.removeValue(forKey: path) != nil {
            writeLog.append("REMOVE:" + path)
            return
        }
        // Remove directory and all children
        if directories.contains(path) {
            let prefix = path + "/"
            files = files.filter { !$0.key.hasPrefix(prefix) }
            directories = directories.filter { !$0.hasPrefix(prefix) && $0 != path }
            writeLog.append("REMOVE:" + path)
            return
        }
        throw Failure.noFile(path)
    }

    func moveItem(from source: String, to destination: String) throws {
        // Move all files under source prefix → destination prefix
        let srcPrefix = source + "/"
        let dstPrefix = destination + "/"
        var moved = false

        // Single file move
        if let content = files[source], !directories.contains(source) {
            files.removeValue(forKey: source)
            files[destination] = content
            writeLog.append(destination)
            Self.registerParents(of: destination, into: &directories)
            return
        }

        // Directory move: relocate all children
        if directories.contains(source) {
            var newFiles: [String: String] = [:]
            for (path, content) in files {
                if path.hasPrefix(srcPrefix) {
                    let relative = String(path.dropFirst(srcPrefix.count))
                    let newPath = dstPrefix + relative
                    newFiles[newPath] = content
                    writeLog.append(newPath)
                } else if path == source {
                    continue
                } else {
                    newFiles[path] = content
                }
            }
            files = newFiles
            var newDirs = Set<String>()
            for dir in directories {
                if dir.hasPrefix(srcPrefix) {
                    let relative = String(dir.dropFirst(srcPrefix.count))
                    newDirs.insert(dstPrefix + relative)
                } else if dir == source {
                    newDirs.insert(destination)
                } else {
                    newDirs.insert(dir)
                }
            }
            directories = newDirs
            // Re-register parents for destination
            Self.registerParents(of: destination, into: &directories)
            moved = true
        }

        if !moved {
            throw Failure.noFile(source)
        }
    }

    func createDirectory(at path: String) throws {
        directories.insert(path)
        Self.registerParents(of: path, into: &directories)
    }

    // MARK: - private

    private static func registerParents(of path: String, into dirs: inout Set<String>) {
        var current = path
        while true {
            let parent = (current as NSString).deletingLastPathComponent
            // Termination: parent is empty (relative paths) OR parent stops
            // shrinking (we hit "/" — `("/" as NSString).deletingLastPathComponent`
            // returns "/" which would otherwise spin forever).
            if parent.isEmpty || parent == current { break }
            dirs.insert(parent)
            current = parent
        }
    }
}
