import Foundation
import TOMLDecoder
import ReliosSupport

/// Loads a `ReleaseSpec` from a path on the injected `FileSystem`.
/// `TOMLDecoder` is intentionally referenced only inside this file —
/// swapping the TOML backend later means touching one function.
public struct SpecLoader: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func load(from path: String) throws -> ReleaseSpec {
        guard fs.fileExists(at: path) else {
            throw SpecLoadError.missing(path: path)
        }

        let raw: String
        do {
            raw = try fs.readUTF8(at: path)
        } catch {
            throw SpecLoadError.unreadable(
                path: path,
                underlying: String(describing: error)
            )
        }

        return try Self.decode(raw, at: path)
    }

    // MARK: - private

    private static func decode(_ raw: String, at path: String) throws -> ReleaseSpec {
        do {
            return try TOMLDecoder().decode(ReleaseSpec.self, from: raw)
        } catch {
            throw SpecLoadError.malformed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }
}
