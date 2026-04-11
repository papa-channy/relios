import XCTest
import ReliosCore

/// Locks the (c-2) Gate 3: bump correctness for all 4 BumpKind cases.
final class SemanticVersionTests: XCTestCase {

    // MARK: - parsing

    func test_parsesValidSemver() throws {
        let v = try SemanticVersion(parsing: "1.2.3")
        XCTAssertEqual(v.major, 1)
        XCTAssertEqual(v.minor, 2)
        XCTAssertEqual(v.patch, 3)
        XCTAssertEqual(v.formatted, "1.2.3")
    }

    func test_throwsOnNonNumericComponents() {
        XCTAssertThrowsError(try SemanticVersion(parsing: "1.a.3"))
    }

    func test_throwsOnTwoComponentVersion() {
        XCTAssertThrowsError(try SemanticVersion(parsing: "1.2"))
    }

    func test_throwsOnNegativeComponents() {
        XCTAssertThrowsError(try SemanticVersion(parsing: "1.-2.3"))
    }

    // MARK: - Gate 3: bump correctness

    func test_gate3_bumpNoneReturnsSameVersion() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.bumped(.none), SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    func test_gate3_bumpPatchIncrementsPatchOnly() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.bumped(.patch), SemanticVersion(major: 1, minor: 2, patch: 4))
    }

    func test_gate3_bumpMinorIncrementsMinorAndResetsPatch() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.bumped(.minor), SemanticVersion(major: 1, minor: 3, patch: 0))
    }

    func test_gate3_bumpMajorIncrementsMajorAndResetsMinorAndPatch() {
        let v = SemanticVersion(major: 1, minor: 2, patch: 3)
        XCTAssertEqual(v.bumped(.major), SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    func test_gate3_bumpFromZeroVersion() {
        let v = SemanticVersion(major: 0, minor: 0, patch: 0)
        XCTAssertEqual(v.bumped(.patch), SemanticVersion(major: 0, minor: 0, patch: 1))
        XCTAssertEqual(v.bumped(.minor), SemanticVersion(major: 0, minor: 1, patch: 0))
        XCTAssertEqual(v.bumped(.major), SemanticVersion(major: 1, minor: 0, patch: 0))
    }
}
