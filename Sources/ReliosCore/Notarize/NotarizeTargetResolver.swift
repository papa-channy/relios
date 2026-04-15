import Foundation
import ReliosSupport

/// Resolves `[notarize].target` to an absolute artifact path.
///
/// Rules:
///   - `.dmg`      → latest `*.dmg` in `[dmg].output_dir` (errors if DMG
///                   section is absent)
///   - `.zip`      → `<appName>-<version>.zip` at project root (errors if
///                   the file isn't present; typically produced by CI)
///   - `.auto`     → `.dmg` when `[dmg].enabled`, otherwise `.zip`
///
/// "Latest DMG" is picked by filesystem mtime, not filename sort, because
/// release filenames can be identical across retries (e.g. v0.1.1.dmg
/// regenerated multiple times in the same job).
public struct NotarizeTargetResolver: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func resolve(
        spec: ReleaseSpec,
        projectRoot: String,
        versionString: String?,
        explicitPath: String?
    ) throws -> String {
        if let p = explicitPath {
            let abs = absolute(p, relativeTo: projectRoot)
            guard fs.fileExists(at: abs) else {
                throw NotarizeError.artifactMissing(path: abs)
            }
            guard abs.hasSuffix(".zip") || abs.hasSuffix(".dmg") else {
                throw NotarizeError.unsupportedArtifact(path: abs)
            }
            return abs
        }

        let notarize = spec.notarize ?? NotarizeSection()
        let target = effectiveTarget(notarize: notarize, spec: spec)

        switch target {
        case .dmg:
            guard let dmg = spec.dmg else {
                throw NotarizeError.artifactMissing(
                    path: "<no [dmg] section in relios.toml>"
                )
            }
            return try pickLatestDMG(in: absolute(dmg.outputDir, relativeTo: projectRoot))

        case .zip:
            let name = spec.app.name
            let candidate: String
            if let v = versionString, !v.isEmpty {
                candidate = "\(projectRoot)/\(name)-\(v).zip"
            } else {
                candidate = "\(projectRoot)/\(name).zip"
            }
            guard fs.fileExists(at: candidate) else {
                throw NotarizeError.artifactMissing(path: candidate)
            }
            return candidate

        case .auto:
            // effectiveTarget never returns .auto; defensive fall-through.
            throw NotarizeError.disabled
        }
    }

    // MARK: - private

    private func effectiveTarget(
        notarize: NotarizeSection,
        spec: ReleaseSpec
    ) -> NotarizeSection.Target {
        if notarize.target != .auto { return notarize.target }
        return (spec.dmg?.enabled == true) ? .dmg : .zip
    }

    private func pickLatestDMG(in dir: String) throws -> String {
        let entries = (try? fs.listDirectory(at: dir)) ?? []
        let dmgs = entries.filter { $0.hasSuffix(".dmg") }
        guard !dmgs.isEmpty else {
            throw NotarizeError.artifactMissing(path: "\(dir)/*.dmg")
        }
        // If only one, trivial. If multiple, pick by mtime (requires real FS).
        if dmgs.count == 1 {
            return dir + "/" + dmgs[0]
        }
        let fm = FileManager.default
        var newest: (String, Date) = (dir + "/" + dmgs[0], .distantPast)
        for name in dmgs {
            let path = dir + "/" + name
            let attrs = try? fm.attributesOfItem(atPath: path)
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
            if mtime > newest.1 {
                newest = (path, mtime)
            }
        }
        return newest.0
    }

    private func absolute(_ path: String, relativeTo root: String) -> String {
        path.hasPrefix("/") ? path : root + "/" + path
    }
}
