import Foundation
import ReliosSupport

/// Creates a `.app` bundle directory structure and copies the binary into it.
///
/// Layout produced:
/// ```
/// <outputPath>/
///   Contents/
///     MacOS/
///       <binaryName>        ← copied from build artifact
///     Resources/            ← created but empty unless icon exists
///     Info.plist            ← written by InfoPlistWriter separately
/// ```
public struct AppBundleAssembler: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    /// Assembles the .app directory at `outputPath` using `binarySourcePath`
    /// as the executable. Returns the path to `Contents/MacOS/<binary>`.
    public func assemble(
        spec: ReleaseSpec,
        binarySourcePath: String,
        outputPath: String,
        projectRoot: String
    ) throws -> String {
        let contentsPath = outputPath + "/Contents"
        let macosPath    = contentsPath + "/MacOS"
        let resourcePath = contentsPath + "/Resources"
        let binaryName   = (spec.build.binaryPath as NSString).lastPathComponent
        let destBinary   = macosPath + "/" + binaryName

        // Copy binary (Mach-O, not text — must use copyFile, not readUTF8)
        do {
            try fs.copyFile(from: binarySourcePath, to: destBinary)
        } catch {
            throw BundleError.binaryUnreadable(
                path: binarySourcePath,
                underlying: String(describing: error)
            )
        }

        // Copy icon if present (optional — failure doesn't block release)
        if let iconPath = spec.assets.iconPath {
            let absoluteIcon = projectRoot + "/" + iconPath
            let iconName = (iconPath as NSString).lastPathComponent
            let destIcon = resourcePath + "/" + iconName
            do {
                try fs.copyFile(from: absoluteIcon, to: destIcon)
            } catch {
                // Icon is optional
            }
        }

        // Copy resource bundle if specified (optional)
        if let rbPath = spec.build.resourceBundlePath {
            let absoluteRB = projectRoot + "/" + rbPath
            let rbName = (rbPath as NSString).lastPathComponent
            let destRB = resourcePath + "/" + rbName
            do {
                try fs.copyFile(from: absoluteRB, to: destRB)
            } catch {
                // Resource bundle is optional
            }
        }

        return destBinary
    }
}
