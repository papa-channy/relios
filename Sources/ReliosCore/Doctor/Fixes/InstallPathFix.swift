import Foundation

/// Creates the parent directory of `[install].path` when it is missing.
///
/// This is the auto-fix counterpart to `InstallPathRule`, which `.warn`s when
/// the parent directory doesn't exist. Creating a directory is additive and
/// idempotent — exactly the kind of safe mutation `--fix` is allowed to make.
/// (The common case, `/Applications`, always exists, so this no-ops there.)
public struct InstallPathFix: DoctorFix {
    public init() {}

    public func apply(_ context: ValidationContext) -> FixResult? {
        let installPath = context.spec.install.path
        let parentDir = (installPath as NSString).deletingLastPathComponent

        // Nothing to fix if the parent already exists.
        guard !context.fs.isDirectory(at: parentDir) else {
            return nil
        }

        do {
            try context.fs.createDirectory(at: parentDir)
            return .fixed(
                "install path parent",
                "Created missing directory \(parentDir)"
            )
        } catch {
            return .failed(
                "install path parent",
                "Could not create \(parentDir): \(error)"
            )
        }
    }
}
