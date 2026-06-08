import Foundation
import ReliosSupport

/// Serializes an `UpdateManifest` to JSON and writes it to disk.
public struct UpdateManifestWriter: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// Encodes `manifest` (pretty, stable key order) and writes it to `path`.
    /// Returns the exact JSON written, so callers can sign those bytes.
    @discardableResult
    public func write(_ manifest: UpdateManifest, to path: String) throws -> String {
        let encoder = JSONEncoder()
        // `.withoutEscapingSlashes` keeps URLs readable (https://… not https:\/\/…);
        // every JSON parser accepts both, but the feed is human-inspected too.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let json: String
        do {
            let data = try encoder.encode(manifest)
            guard let s = String(data: data, encoding: .utf8) else {
                throw UpdateError.writeFailed(path: path, underlying: "UTF-8 encoding failed")
            }
            json = s
        } catch let e as UpdateError {
            throw e
        } catch {
            throw UpdateError.writeFailed(path: path, underlying: String(describing: error))
        }

        do {
            try fs.writeUTF8(json, to: path)
        } catch {
            throw UpdateError.writeFailed(path: path, underlying: String(describing: error))
        }
        return json
    }
}
