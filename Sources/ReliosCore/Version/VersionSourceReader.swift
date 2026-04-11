import Foundation
import ReliosSupport

/// Reads `(SemanticVersion, BuildNumber)` from a Swift source file using the
/// regex patterns declared in `[version]`.
///
/// Read-only by design: there is no companion `update` method in this slice.
/// `VersionSourceUpdater` lands when the release pipeline starts writing,
/// not before — that is the structural guarantee that `relios doctor` and
/// `relios release --dry-run` cannot accidentally mutate the source file.
public struct VersionSourceReader: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func read(
        spec versionSpec: VersionSection,
        at sourcePath: String
    ) throws -> (version: SemanticVersion, build: BuildNumber) {
        let raw: String
        do {
            raw = try fs.readUTF8(at: sourcePath)
        } catch {
            throw VersionSourceError.unreadable(
                path: sourcePath,
                underlying: String(describing: error)
            )
        }

        guard let versionMatch = Self.firstCapture(in: raw, pattern: versionSpec.versionPattern) else {
            throw VersionSourceError.versionPatternUnmatched(
                path: sourcePath,
                pattern: versionSpec.versionPattern
            )
        }
        let version = try SemanticVersion(parsing: versionMatch)

        guard let buildMatch = Self.firstCapture(in: raw, pattern: versionSpec.buildPattern) else {
            throw VersionSourceError.buildPatternUnmatched(
                path: sourcePath,
                pattern: versionSpec.buildPattern
            )
        }
        let build = try BuildNumber(parsing: buildMatch)

        return (version, build)
    }

    // MARK: - private

    /// Returns the first capture group of `pattern` in `source`, or nil if
    /// the pattern doesn't compile or doesn't match.
    private static func firstCapture(in source: String, pattern: String) -> String? {
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
        return String(source[captureRange])
    }
}
