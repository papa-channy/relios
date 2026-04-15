import XCTest
import ReliosCore

final class NotarizerCredentialsTests: XCTestCase {

    func test_readsAllThreeFromEnv() throws {
        let creds = try NotarizerCredentials.fromEnvironment([
            "APPLE_ID": "dev@example.com",
            "APPLE_APP_SPECIFIC_PASSWORD": "abcd-efgh-ijkl-mnop",
            "APPLE_TEAM_ID": "ABCDE12345",
        ])
        XCTAssertEqual(creds.appleID, "dev@example.com")
        XCTAssertEqual(creds.password, "abcd-efgh-ijkl-mnop")
        XCTAssertEqual(creds.teamID, "ABCDE12345")
    }

    func test_reportsAllMissingVarsTogether() {
        XCTAssertThrowsError(try NotarizerCredentials.fromEnvironment([:])) { err in
            guard case NotarizeError.missingCredentials(let vars) = err else {
                return XCTFail("expected .missingCredentials, got \(err)")
            }
            XCTAssertEqual(vars, [
                "APPLE_ID",
                "APPLE_APP_SPECIFIC_PASSWORD",
                "APPLE_TEAM_ID",
            ])
        }
    }

    func test_emptyStringCountsAsMissing() {
        XCTAssertThrowsError(try NotarizerCredentials.fromEnvironment([
            "APPLE_ID": "",
            "APPLE_APP_SPECIFIC_PASSWORD": "pw",
            "APPLE_TEAM_ID": "ABCDE12345",
        ])) { err in
            guard case NotarizeError.missingCredentials(let vars) = err else {
                return XCTFail("expected .missingCredentials, got \(err)")
            }
            XCTAssertEqual(vars, ["APPLE_ID"])
        }
    }
}
