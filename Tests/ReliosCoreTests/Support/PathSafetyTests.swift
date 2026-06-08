import XCTest
import ReliosSupport

final class PathSafetyTests: XCTestCase {

    func test_normalize() {
        XCTAssertEqual(PathSafety.normalize("a/./b"), "a/b")
        XCTAssertEqual(PathSafety.normalize("a/b/../c"), "a/c")
        XCTAssertEqual(PathSafety.normalize("a//b///c"), "a/b/c")
        XCTAssertEqual(PathSafety.normalize("/p/dist/../x"), "/p/x")
        XCTAssertEqual(PathSafety.normalize("/a/../.."), "/")
        XCTAssertEqual(PathSafety.normalize("../x"), "../x")     // relative may climb
        XCTAssertEqual(PathSafety.normalize("."), ".")
    }

    func test_isWithin_respectsBoundaries() {
        XCTAssertTrue(PathSafety.isWithin("/p/dist/x", root: "/p/dist"))
        XCTAssertTrue(PathSafety.isWithin("/p/dist", root: "/p/dist"))
        XCTAssertFalse(PathSafety.isWithin("/p/other", root: "/p/dist"))
        // boundary: a sibling that merely shares a prefix string is NOT within
        XCTAssertFalse(PathSafety.isWithin("/p/distractor", root: "/p/dist"))
        XCTAssertFalse(PathSafety.isWithin("/p/dist/../evil", root: "/p/dist"))
    }

    func test_resolveWithinRoot() throws {
        XCTAssertEqual(try PathSafety.resolveWithinRoot("dist/App.app", root: "/p"), "/p/dist/App.app")
        XCTAssertThrowsError(try PathSafety.resolveWithinRoot("/Applications/X.app", root: "/p"))
        XCTAssertThrowsError(try PathSafety.resolveWithinRoot("../../etc/passwd", root: "/p"))
    }

    func test_dangerousTargets() {
        let home = "/Users/me"
        let root = "/p"
        XCTAssertTrue(PathSafety.isDangerousTarget("/", projectRoot: root, homeDir: home))
        XCTAssertTrue(PathSafety.isDangerousTarget("/Users/me", projectRoot: root, homeDir: home))
        XCTAssertTrue(PathSafety.isDangerousTarget("/p", projectRoot: root, homeDir: home))
        XCTAssertFalse(PathSafety.isDangerousTarget("/Applications/X.app", projectRoot: root, homeDir: home))
        XCTAssertThrowsError(try PathSafety.assertSafeDestructiveTarget("/", projectRoot: root, homeDir: home))
        XCTAssertNoThrow(try PathSafety.assertSafeDestructiveTarget("/Applications/X.app", projectRoot: root, homeDir: home))
    }

    func test_extractionZipSlip() {
        XCTAssertNoThrow(try PathSafety.assertExtractionWithin(["App.app", "App.app/Contents/x"], targetDir: "/t"))
        XCTAssertThrowsError(try PathSafety.assertExtractionWithin(["../evil"], targetDir: "/t"))
        XCTAssertThrowsError(try PathSafety.assertExtractionWithin(["/etc/passwd"], targetDir: "/t"))
        XCTAssertThrowsError(try PathSafety.assertExtractionWithin(["ok/../../escape"], targetDir: "/t"))
    }
}
