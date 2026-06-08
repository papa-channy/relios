import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

/// Acquires the project lock for a mutating command, emitting a failure (human
/// or JSON) and exiting if another live run holds it. The caller must
/// `defer { lock.release(projectRoot:) }`.
func acquireProjectLock(command: String, projectRoot: String, json: Bool) throws -> ProjectLock {
    let lock = ProjectLock(
        fs: RealFileSystem(),
        pid: ProcessInfo.processInfo.processIdentifier,
        hostname: ProcessInfo.processInfo.hostName
    )
    do {
        try lock.acquire(command: command, projectRoot: projectRoot)
    } catch let error as LockError {
        if json {
            Report.failure(command: command, code: error.code,
                           reason: error.shortReason, fix: error.shortFix)
        } else {
            print("[\(command)] failed")
            print("  Reason: \(error.shortReason)")
            print("  Fix: \(error.shortFix)")
        }
        throw ExitCode.failure
    }
    return lock
}
