import Foundation
import ReliosSupport

/// Inspects and repairs leftover state from an interrupted (hard-killed) run.
///
/// Because the install/rollback paths use a move-aside → move-into-place →
/// restore-on-failure pattern (see `AppInstaller`, `RollbackRunner`), a clean
/// failure self-heals. The only residue a *hard kill* (where `defer` never ran)
/// can leave is: a stale `.relios/lock`, a disposable scratch dir, and a stash
/// of the previous app (`*.relios-old` / `*.relios-rollback-old`). This runner
/// reports those (`scan`, read-only) and resolves them (`recover`):
///   - stale lock           → remove
///   - scratch dir          → remove (disposable)
///   - stash + install present  → remove stash (op completed; stash is leftover)
///   - stash + install MISSING  → restore stash → install (op interrupted mid-move)
public struct RecoverRunner: Sendable {
    private let fs: any FileSystem
    private let liveness: any ProcessLiveness
    private let pid: Int32
    private let hostname: String

    public init(
        fs: any FileSystem,
        liveness: any ProcessLiveness = RealProcessLiveness(),
        pid: Int32,
        hostname: String
    ) {
        self.fs = fs
        self.liveness = liveness
        self.pid = pid
        self.hostname = hostname
    }

    public enum Action: String, Encodable, Sendable {
        case removeStaleLock = "remove_stale_lock"
        case removeScratch = "remove_scratch"
        case removeLeftoverStash = "remove_leftover_stash"
        case restoreStash = "restore_stash"
    }

    public struct Finding: Encodable, Sendable, Equatable {
        public let action: Action
        public let path: String
    }

    public struct Report: Encodable, Sendable, Equatable {
        public let lockHolder: LockInfo?
        public let lockStale: Bool
        public let findings: [Finding]
        public var clean: Bool { lockHolder == nil && findings.isEmpty }

        enum CodingKeys: String, CodingKey {
            case lockHolder = "lock_holder"
            case lockStale = "lock_stale"
            case findings
            case clean
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(lockHolder, forKey: .lockHolder)
            try c.encode(lockStale, forKey: .lockStale)
            try c.encode(findings, forKey: .findings)
            try c.encode(clean, forKey: .clean)
        }
    }

    /// Read-only: what's present and what `recover` would do.
    public func scan(spec: ReleaseSpec, projectRoot: String) -> Report {
        let lock = ProjectLock(fs: fs, liveness: liveness, pid: pid, hostname: hostname)
        let holder = lock.current(projectRoot: projectRoot)
        let stale = isStale(holder)

        var findings: [Finding] = []
        if let holder, stale {
            _ = holder
            findings.append(Finding(action: .removeStaleLock, path: ProjectLock.path(projectRoot: projectRoot)))
        }
        for leftover in leftovers(spec: spec) {
            findings.append(leftover)
        }
        return Report(lockHolder: holder, lockStale: stale, findings: findings)
    }

    /// Applies the recovery actions (unless `dryRun`). Returns what was done
    /// (or would be done). Only ever touches `.relios`/`*.relios-*` paths and
    /// the install target it restores.
    @discardableResult
    public func recover(spec: ReleaseSpec, projectRoot: String, dryRun: Bool) -> [Finding] {
        let report = scan(spec: spec, projectRoot: projectRoot)
        guard !dryRun else { return report.findings }

        for finding in report.findings {
            switch finding.action {
            case .removeStaleLock, .removeScratch, .removeLeftoverStash:
                try? fs.removeItem(at: finding.path)
            case .restoreStash:
                // path is the stash; restore it to the install target.
                let installPath = spec.install.path
                try? fs.moveItem(from: finding.path, to: installPath)
            }
        }
        return report.findings
    }

    // MARK: - private

    private func isStale(_ holder: LockInfo?) -> Bool {
        guard let holder else { return false }
        if holder.hostname != hostname { return false }   // can't verify another host
        return !liveness.isAlive(holder.pid)
    }

    private func leftovers(spec: ReleaseSpec) -> [Finding] {
        let installPath = spec.install.path
        let parent = (installPath as NSString).deletingLastPathComponent
        var out: [Finding] = []

        let scratch = parent + "/.relios-rollback-scratch"
        if fs.isDirectory(at: scratch) {
            out.append(Finding(action: .removeScratch, path: scratch))
        }

        let installPresent = fs.fileExists(at: installPath)
        for suffix in [".relios-rollback-old", ".relios-old"] {
            let stash = installPath + suffix
            guard fs.fileExists(at: stash) else { continue }
            if installPresent {
                out.append(Finding(action: .removeLeftoverStash, path: stash))
            } else {
                out.append(Finding(action: .restoreStash, path: stash))
            }
        }
        return out
    }
}
