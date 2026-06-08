import XCTest
import ReliosCore
import ReliosSupport

struct FakeLiveness: ProcessLiveness {
    let alive: Set<Int32>
    func isAlive(_ pid: Int32) -> Bool { alive.contains(pid) }
}

final class ProjectLockTests: XCTestCase {

    func test_acquireWritesLock() throws {
        let fs = InMemoryFileSystem()
        let lock = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [100]), pid: 100, hostname: "h1")
        try lock.acquire(command: "release", projectRoot: "/p")

        let info = try XCTUnwrap(lock.current(projectRoot: "/p"))
        XCTAssertEqual(info.pid, 100)
        XCTAssertEqual(info.command, "release")
        XCTAssertEqual(info.hostname, "h1")
        XCTAssertTrue(fs.fileExists(at: "/p/.relios/lock"))
    }

    func test_heldByLiveOtherPidIsRefused() throws {
        let fs = InMemoryFileSystem()
        let holder = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [200]), pid: 200, hostname: "h1")
        try holder.acquire(command: "release", projectRoot: "/p")

        let me = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [200]), pid: 100, hostname: "h1")
        XCTAssertThrowsError(try me.acquire(command: "install", projectRoot: "/p")) { error in
            guard case .held(let by) = (error as? LockError) else { return XCTFail("expected .held") }
            XCTAssertEqual(by.pid, 200)
        }
    }

    func test_staleLockFromDeadPidIsReclaimed() throws {
        let fs = InMemoryFileSystem()
        let dead = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [300]), pid: 300, hostname: "h1")
        try dead.acquire(command: "release", projectRoot: "/p")

        // pid 300 is no longer alive → a new run reclaims the lock.
        let fresh = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [100]), pid: 100, hostname: "h1")
        XCTAssertNoThrow(try fresh.acquire(command: "release", projectRoot: "/p"))
        XCTAssertEqual(fresh.current(projectRoot: "/p")?.pid, 100)
    }

    func test_lockFromAnotherHostIsRefused() throws {
        let fs = InMemoryFileSystem()
        let otherHost = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [200]), pid: 200, hostname: "h2")
        try otherHost.acquire(command: "release", projectRoot: "/p")

        let me = ProjectLock(fs: fs, liveness: FakeLiveness(alive: []), pid: 100, hostname: "h1")
        XCTAssertThrowsError(try me.acquire(command: "release", projectRoot: "/p")) { error in
            guard case .heldByAnotherHost = (error as? LockError) else { return XCTFail("expected .heldByAnotherHost") }
        }
    }

    func test_releaseRemovesLock() throws {
        let fs = InMemoryFileSystem()
        let lock = ProjectLock(fs: fs, liveness: FakeLiveness(alive: [100]), pid: 100, hostname: "h1")
        try lock.acquire(command: "release", projectRoot: "/p")
        lock.release(projectRoot: "/p")
        XCTAssertNil(lock.current(projectRoot: "/p"))
    }
}
