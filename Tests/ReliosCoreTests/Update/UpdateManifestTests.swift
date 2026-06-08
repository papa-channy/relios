import XCTest
import ReliosCore
import ReliosSupport

/// Locks the JSON shape of the update feed — the contract the shipped app reads.
final class UpdateManifestTests: XCTestCase {

    private func sample() -> UpdateManifest {
        UpdateManifest(
            appName: "Demo",
            bundleId: "com.example.demo",
            version: "2.0.1",
            build: "7",
            url: "https://github.com/o/r/releases/download/v2.0.1/Demo-2.0.1.dmg",
            notes: "- Fixed a thing\n- Improved another",
            notesURL: "https://github.com/o/r/releases/tag/v2.0.1",
            minMacOS: "14.0",
            publishedAt: "2026-06-07T00:00:00Z"
        )
    }

    func test_encodesSnakeCaseKeys() throws {
        let fs = InMemoryFileSystem()
        try UpdateManifestWriter(fs: fs).write(sample(), to: "/out/update.json")

        let json = try fs.readUTF8(at: "/out/update.json")
        XCTAssertTrue(json.contains("\"app_name\""))
        XCTAssertTrue(json.contains("\"bundle_id\""))
        XCTAssertTrue(json.contains("\"notes_url\""))
        XCTAssertTrue(json.contains("\"min_macos\""))
        XCTAssertTrue(json.contains("\"published_at\""))
        XCTAssertTrue(json.contains("Demo-2.0.1.dmg"))
    }

    func test_roundTrips() throws {
        let fs = InMemoryFileSystem()
        try UpdateManifestWriter(fs: fs).write(sample(), to: "/out/update.json")

        let json = try fs.readUTF8(at: "/out/update.json")
        let decoded = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, sample())
    }
}
