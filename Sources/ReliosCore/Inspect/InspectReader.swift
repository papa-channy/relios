import Foundation
import ReliosSupport

/// Reads the latest release manifest for `relios inspect`.
public struct InspectReader: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func readLatest(releasesDir: String) throws -> ReleaseManifest {
        let path = releasesDir + "/latest.json"
        guard fs.fileExists(at: path) else {
            throw ManifestError.latestNotFound(path: path)
        }
        let raw: String
        do {
            raw = try fs.readUTF8(at: path)
        } catch {
            throw ManifestError.decodingFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
        guard let data = raw.data(using: .utf8) else {
            throw ManifestError.decodingFailed(path: path, underlying: "Not UTF-8")
        }
        do {
            return try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw ManifestError.decodingFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }
}
