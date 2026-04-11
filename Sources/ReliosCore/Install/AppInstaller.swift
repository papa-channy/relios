import Foundation
import ReliosSupport

/// Installs a .app bundle to [install].path.
///
/// Atomic strategy:
///   1. If target exists, move to temp location first (not delete)
///   2. Copy new .app to target
///   3. Remove temp
///   If step 2 fails, restore from temp → target is preserved.
public struct AppInstaller: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func install(from source: String, to destination: String) throws {
        let tempPath = destination + ".relios-old"

        // 1. Move existing app aside (atomic-safe: if copy fails, we restore)
        let hadExisting = fs.fileExists(at: destination)
        if hadExisting {
            do {
                try fs.moveItem(from: destination, to: tempPath)
            } catch {
                throw InstallError.installFailed(
                    reason: "Could not move existing app aside: \(error)"
                )
            }
        }

        // 2. Copy new .app to destination
        do {
            try fs.copyFile(from: source, to: destination)
        } catch {
            // Restore old app if we moved it
            if hadExisting {
                try? fs.moveItem(from: tempPath, to: destination)
            }
            throw InstallError.installFailed(
                reason: "Could not copy new app to \(destination): \(error)"
            )
        }

        // 3. Clean up old app
        if hadExisting {
            try? fs.removeItem(at: tempPath)
        }
    }
}
