import Foundation
import ReliosSupport

/// Generates an `Info.plist` from the release spec and writes it into
/// the bundle's `Contents/` directory.
///
/// v1 supports `plist_mode = "generate"` only. The struct accepts `mode`
/// so the public API is future-proof for `merge` without changing callers.
public struct InfoPlistWriter: Sendable {
    public enum Mode: Sendable, Equatable {
        case generate
    }

    private let fs: any FileSystem
    private let mode: Mode

    public init(fs: any FileSystem, mode: Mode = .generate) {
        self.fs = fs
        self.mode = mode
    }

    public func write(
        spec: ReleaseSpec,
        version: SemanticVersion,
        build: BuildNumber,
        toContentsDir contentsPath: String
    ) throws {
        switch mode {
        case .generate:
            try writeGenerated(
                spec: spec,
                version: version,
                build: build,
                contentsPath: contentsPath
            )
        }
    }

    // MARK: - private

    private func writeGenerated(
        spec: ReleaseSpec,
        version: SemanticVersion,
        build: BuildNumber,
        contentsPath: String
    ) throws {
        let binaryName = (spec.build.binaryPath as NSString).lastPathComponent
        let dict: [String: Any] = [
            "CFBundleExecutable": binaryName,
            "CFBundleIdentifier": spec.app.bundleId,
            "CFBundleName": spec.app.displayName,
            "CFBundleDisplayName": spec.app.displayName,
            "CFBundleShortVersionString": version.formatted,
            "CFBundleVersion": build.formatted,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": spec.app.minMacOS,
            "LSApplicationCategoryType": spec.app.category,
        ]

        let plistPath = contentsPath + "/Info.plist"

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .xml,
                options: 0
            )
            guard let xmlString = String(data: data, encoding: .utf8) else {
                throw BundleError.plistWriteFailed(
                    path: plistPath,
                    underlying: "Could not encode plist as UTF-8"
                )
            }
            try fs.writeUTF8(xmlString, to: plistPath)
        } catch let error as BundleError {
            throw error
        } catch {
            throw BundleError.plistWriteFailed(
                path: plistPath,
                underlying: String(describing: error)
            )
        }
    }
}
