import XCTest
import ReliosCore

final class BuildNumberTests: XCTestCase {

    func test_parsesValidIntegerString() throws {
        let n = try BuildNumber(parsing: "17")
        XCTAssertEqual(n.value, 17)
        XCTAssertEqual(n.formatted, "17")
    }

    func test_throwsOnNonInteger() {
        XCTAssertThrowsError(try BuildNumber(parsing: "x"))
    }

    func test_throwsOnNegative() {
        XCTAssertThrowsError(try BuildNumber(parsing: "-1"))
    }

    func test_incrementedReturnsNextValue() {
        XCTAssertEqual(BuildNumber(17).incremented(), BuildNumber(18))
        XCTAssertEqual(BuildNumber(0).incremented(), BuildNumber(1))
    }

    func test_initialIsOne() {
        XCTAssertEqual(BuildNumber.initial, BuildNumber(1))
    }
}
