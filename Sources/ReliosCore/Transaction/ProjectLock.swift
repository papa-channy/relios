import Foundation
import ReliosSupport

/// Records who holds the project lock. Written to `.relios/lock` as JSON.
public struct LockInfo: Codable, Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let startedAt: String
    public let hostname: String

    public init(pid: Int32, command: String, startedAt: String, hostname: String) {
        self.pid = pid
        self.command = command
        self.startedAt = startedAt
        self.hostname = hostname
    }

    enum CodingKeys: String, CodingKey {
        case pid, command
        case startedAt = "started_at"
        case hostname
    }
}

public enum LockError: Error, Equatable {
    case held(by: LockInfo)
    case heldByAnotherHost(by: LockInfo)
}

extension LockError {
    public var code: DiagnosticCode {
        switch self {
        case .held:              return DiagnosticCode("LOCK_HELD")
        case .heldByAnotherHost: return DiagnosticCode("LOCK_HELD_ANOTHER_HOST")
        }
    }
    public var shortReason: String {
        switch self {
        case .held(let info):
            return "Another relios `\(info.command)` (pid \(info.pid)) is running in this project"
        case .heldByAnotherHost(let info):
            return "Locked by host \(info.hostname) (pid \(info.pid)); cannot verify it's still alive"
        }
    }
    public var shortFix: String {
        "Wait for it to finish, or run `relios recover` if the process is gone"
    }
}

/// Process-liveness probe (injectable so tests don't depend on real pids).
public protocol ProcessLiveness: Sendable {
    func isAlive(_ pid: Int32) -> Bool
}

public struct RealProcessLiveness: ProcessLiveness {
    public init() {}
    public func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        // kill(pid, 0) probes existence without signaling; EPERM means it
        // exists but we can't signal it (still alive).
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

/// A per-project advisory lock at `.relios/lock`. Prevents two mutating relios
/// commands from racing in the same project (double version bump, backup
/// rotation clobber, install-target contention).
///
/// Stale locks (the holder's pid is dead, same host) are reclaimed
/// automatically. A lock held by a live pid on this host is refused. A lock
/// from another host is refused (we can't verify its liveness).
public struct ProjectLock: Sendable {
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

    public static func path(projectRoot: String) -> String {
        projectRoot + "/.relios/lock"
    }

    /// Reads the current lock holder, if any (and decodable).
    public func current(projectRoot: String) -> LockInfo? {
        let path = Self.path(projectRoot: projectRoot)
        guard fs.fileExists(at: path),
              let raw = try? fs.readUTF8(at: path),
              let info = try? JSONDecoder().decode(LockInfo.self, from: Data(raw.utf8)) else {
            return nil
        }
        return info
    }

    public func acquire(command: String, projectRoot: String, now: Date = Date()) throws {
        let path = Self.path(projectRoot: projectRoot)
        if let info = current(projectRoot: projectRoot) {
            if info.hostname != hostname {
                throw LockError.heldByAnotherHost(by: info)
            }
            if info.pid != pid && liveness.isAlive(info.pid) {
                throw LockError.held(by: info)
            }
            // Otherwise the holder is dead (stale) or it's us — reclaim.
        }
        try? fs.createDirectory(at: projectRoot + "/.relios")
        let info = LockInfo(pid: pid, command: command, startedAt: Self.iso(now), hostname: hostname)
        let data = try JSONEncoder().encode(info)
        try fs.writeUTF8(String(decoding: data, as: UTF8.self), to: path)
    }

    public func release(projectRoot: String) {
        try? fs.removeItem(at: Self.path(projectRoot: projectRoot))
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
