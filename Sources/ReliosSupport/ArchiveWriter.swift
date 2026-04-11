import Foundation

/// Boundary protocol for creating zip archives.
/// Production: `DittoArchiveWriter`. Tests: `MockArchiveWriter`.
public protocol ArchiveWriter: Sendable {
    func writeArchive(source: String, destination: String) throws
}

/// Uses `/usr/bin/ditto -c -k --keepParent` to create a zip that preserves
/// macOS metadata (xattr, resource forks).
public struct DittoArchiveWriter: ArchiveWriter {
    private let process: ProcessRunner

    public init(process: ProcessRunner) {
        self.process = process
    }

    public func writeArchive(source: String, destination: String) throws {
        // Ensure parent dir exists
        let destDir = (destination as NSString).deletingLastPathComponent
        let fm = FileManager.default
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true, attributes: nil)

        let command = "/usr/bin/ditto -c -k --keepParent '\(source)' '\(destination)'"
        let result = try process.runShell(command, cwd: nil)
        guard result.exitCode == 0 else {
            throw ArchiveError.dittoFailed(
                source: source,
                destination: destination,
                exitCode: result.exitCode,
                stderrTail: String(result.stderr.suffix(500))
            )
        }
    }
}

public enum ArchiveError: Error, Equatable {
    case dittoFailed(source: String, destination: String, exitCode: Int32, stderrTail: String)
}
