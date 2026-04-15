import XCTest
import ReliosCore
import ReliosSupport

final class KeychainIdentityTests: XCTestCase {

    func test_parsesTeamIDFromStandardIdentity() {
        let id = KeychainIdentity(hash: String(repeating: "a", count: 40),
                                  name: "Developer ID Application: Chan (ABCDE12345)")
        XCTAssertEqual(id.teamID, "ABCDE12345")
    }

    func test_returnsNilForNonStandardIdentity() {
        XCTAssertNil(KeychainIdentity.parseTeamID(from: "Mac Developer"))
        XCTAssertNil(KeychainIdentity.parseTeamID(from: "Identity (short)"))
        XCTAssertNil(KeychainIdentity.parseTeamID(from: "Identity (has spaces)"))
    }

    func test_parsesFindIdentityOutput() {
        let output = """
        Policy: Code Signing
          Matching identities
          1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Chan (ABCDE12345)"
          2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Apple Development: chan@example.com (XYZ9876543)"
             2 identities found
        """
        let identities = KeychainIdentityLister.parse(output)
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(identities[0].name, "Developer ID Application: Chan (ABCDE12345)")
        XCTAssertEqual(identities[0].teamID, "ABCDE12345")
        XCTAssertEqual(identities[1].teamID, "XYZ9876543")
    }

    func test_returnsEmptyForNoIdentitiesMessage() {
        let output = "  0 identities found"
        XCTAssertTrue(KeychainIdentityLister.parse(output).isEmpty)
    }
}
