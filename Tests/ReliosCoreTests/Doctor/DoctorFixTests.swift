import XCTest
import ReliosCore
import ReliosSupport

/// `relios doctor --fix`: safe, additive auto-fixes.
final class DoctorFixTests: XCTestCase {

    private func context(fs: InMemoryFileSystem) -> ValidationContext {
        ValidationContext(
            spec: TestSpecBuilder.spec(signingMode: .adhoc),
            projectRoot: "/proj",
            fs: fs
        )
    }

    // InstallPathFix creates the missing parent directory of [install].path.
    func test_installPathFix_createsMissingParent() throws {
        // /Applications is NOT registered → parent missing.
        let fs = InMemoryFileSystem(files: [:])
        XCTAssertFalse(fs.isDirectory(at: "/Applications"))

        let result = InstallPathFix().apply(context(fs: fs))

        XCTAssertEqual(result?.status, .fixed)
        XCTAssertTrue(fs.isDirectory(at: "/Applications"), "parent dir should now exist")
    }

    // No-op (returns nil) when the parent directory already exists.
    func test_installPathFix_noOpWhenParentExists() throws {
        let fs = InMemoryFileSystem(directories: ["/Applications"])

        let result = InstallPathFix().apply(context(fs: fs))

        XCTAssertNil(result, "should return nil when there is nothing to fix")
    }

    // DoctorFixer collects only the fixes that applied.
    func test_doctorFixer_collectsAppliedFixes() throws {
        let fs = InMemoryFileSystem(files: [:])
        let fixer = DoctorFixer(fixes: [InstallPathFix()])

        let results = fixer.run(context(fs: fs))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.status, .fixed)
    }

    // DoctorFixer returns empty when nothing needs fixing.
    func test_doctorFixer_emptyWhenNothingToFix() throws {
        let fs = InMemoryFileSystem(directories: ["/Applications"])
        let fixer = DoctorFixer(fixes: [InstallPathFix()])

        let results = fixer.run(context(fs: fs))

        XCTAssertTrue(results.isEmpty)
    }
}
