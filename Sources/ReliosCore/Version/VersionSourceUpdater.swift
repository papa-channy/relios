import Foundation
import ReliosSupport

/// Atomically rewrites `version` and `build` in a Swift source file by
/// replacing the first regex-captured group in each pattern.
///
/// Read-only counterpart is `VersionSourceReader`. These two are separate
/// types (not methods on one type) so that `doctor` and `dry-run` can
/// depend on the reader without pulling in write capability.
public struct VersionSourceUpdater: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// Reads the source file, replaces both captured groups, writes back.
    /// If either pattern fails to match, the file is NOT modified and an
    /// error is thrown — this is the "build succeeds before version source
    /// is touched" safety guarantee from the design doc.
    public func update(
        at path: String,
        versionPattern: String,
        newVersion: SemanticVersion,
        buildPattern: String,
        newBuild: BuildNumber
    ) throws {
        var content: String
        do {
            content = try fs.readUTF8(at: path)
        } catch {
            throw VersionSourceError.unreadable(
                path: path,
                underlying: String(describing: error)
            )
        }

        guard let updatedWithVersion = Self.replaceFirstCapture(
            in: content,
            pattern: versionPattern,
            replacement: newVersion.formatted
        ) else {
            throw VersionSourceError.versionPatternUnmatched(
                path: path,
                pattern: versionPattern
            )
        }
        content = updatedWithVersion

        guard let updatedWithBuild = Self.replaceFirstCapture(
            in: content,
            pattern: buildPattern,
            replacement: newBuild.formatted
        ) else {
            throw VersionSourceError.buildPatternUnmatched(
                path: path,
                pattern: buildPattern
            )
        }
        content = updatedWithBuild

        try fs.writeUTF8(content, to: path)
    }

    // MARK: - private

    /// Replaces the first capture group of `pattern` with `replacement`,
    /// leaving everything else in the string untouched.
    private static func replaceFirstCapture(
        in source: String,
        pattern: String,
        replacement: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        var result = source
        result.replaceSubrange(captureRange, with: replacement)
        return result
    }
}
