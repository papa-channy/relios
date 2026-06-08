import Foundation
import ReliosSupport

/// Writes a `ReleaseManifest` to `latest.json` and a timestamped copy in `history/`.
public struct ReleaseManifestWriter: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// Writes manifest to both locations. `releasesDir` is typically `dist/releases`.
    public func write(_ manifest: ReleaseManifest, releasesDir: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(manifest)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ManifestError.encodingFailed
        }

        // latest.json — overwritten each release
        let latestPath = releasesDir + "/latest.json"
        try fs.writeUTF8(json, to: latestPath)

        // history/<timestamp>.json — append-only
        let historyDir = releasesDir + "/history"
        let safeName = manifest.timestamp
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "T")
        let historyPath = historyDir + "/" + safeName + ".json"
        try fs.writeUTF8(json, to: historyPath)
    }
}

public enum ManifestError: Error, Equatable {
    case encodingFailed
    case latestNotFound(path: String)
    case decodingFailed(path: String, underlying: String)
}

extension ManifestError {
    public var code: DiagnosticCode {
        switch self {
        case .encodingFailed: return DiagnosticCode("MANIFEST_ENCODING_FAILED")
        case .latestNotFound: return DiagnosticCode("MANIFEST_NOT_FOUND")
        case .decodingFailed: return DiagnosticCode("MANIFEST_DECODING_FAILED")
        }
    }

    public var shortReason: String {
        switch self {
        case .encodingFailed:
            return "Could not encode the release manifest"
        case .latestNotFound:
            return "No release manifest found"
        case .decodingFailed(let path, let underlying):
            return "Could not read release manifest at \(path): \(underlying)"
        }
    }

    public var shortFix: String {
        switch self {
        case .encodingFailed:
            return "This is a bug — report it"
        case .latestNotFound:
            return "Run `relios release` first"
        case .decodingFailed:
            return "The manifest may be corrupt; re-run `relios release`"
        }
    }
}
