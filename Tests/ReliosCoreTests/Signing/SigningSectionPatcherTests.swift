import XCTest
import ReliosCore

final class SigningSectionPatcherTests: XCTestCase {

    func test_replacesExistingSigningBlock() {
        let input = """
        [bundle]
        output_path = "dist/X.app"

        [signing]
        mode = "adhoc"

        [install]
        path = "/Applications/X.app"
        """
        let values = SigningSectionPatcher.Values(
            mode: .developerID,
            identity: "Developer ID Application: Chan (ABCDE12345)",
            teamID: "ABCDE12345"
        )
        let patched = SigningSectionPatcher().patch(input, with: values)

        XCTAssertTrue(patched.contains("mode = \"developer-id\""))
        XCTAssertTrue(patched.contains("identity = \"Developer ID Application: Chan (ABCDE12345)\""))
        XCTAssertTrue(patched.contains("team_id = \"ABCDE12345\""))
        XCTAssertTrue(patched.contains("hardened_runtime = true"))
        XCTAssertTrue(patched.contains("[install]"), "subsequent sections must survive")
        XCTAssertTrue(patched.contains("[bundle]"), "prior sections must survive")
        XCTAssertFalse(patched.contains("mode = \"adhoc\""), "old signing values must be gone")
    }

    func test_replacesWhenSigningIsLastSection() {
        let input = """
        [bundle]
        output_path = "dist/X.app"

        [signing]
        mode = "adhoc"
        """
        let values = SigningSectionPatcher.Values(mode: .keep)
        let patched = SigningSectionPatcher().patch(input, with: values)

        XCTAssertTrue(patched.contains("mode = \"keep\""))
        XCTAssertTrue(patched.contains("[bundle]"))
    }

    func test_appendsWhenNoSigningSectionExists() {
        let input = """
        [bundle]
        output_path = "dist/X.app"
        """
        let values = SigningSectionPatcher.Values(mode: .adhoc)
        let patched = SigningSectionPatcher().patch(input, with: values)

        XCTAssertTrue(patched.contains("[bundle]"))
        XCTAssertTrue(patched.contains("[signing]"))
        XCTAssertTrue(patched.contains("mode = \"adhoc\""))
    }

    func test_emitsFalseForHardenedRuntimeWhenDisabled() {
        let values = SigningSectionPatcher.Values(
            mode: .developerID,
            identity: "id",
            teamID: "T",
            hardenedRuntime: false
        )
        let patched = SigningSectionPatcher().patch("[signing]\nmode = \"adhoc\"", with: values)
        XCTAssertTrue(patched.contains("hardened_runtime = false"))
    }
}
