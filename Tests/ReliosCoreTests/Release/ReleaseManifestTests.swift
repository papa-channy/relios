import XCTest
import Foundation
import ReliosCore
import ReliosSupport

/// Gates 1-4: manifest creation, history, idempotency, dry-run safety.
final class ReleaseManifestTests: XCTestCase {

    // Gate 1: non-dry-run writes latest.json with correct values
    func test_gate1_writesLatestJsonWithCorrectValues() throws {
        let fs = InMemoryFileSystem()
        let writer = ReleaseManifestWriter(fs: fs)
        let manifest = makeManifest(version: "1.0.1", build: "1")

        try writer.write(manifest, releasesDir: "/proj/dist/releases")

        let raw = try fs.readUTF8(at: "/proj/dist/releases/latest.json")
        let data = raw.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ReleaseManifest.self, from: data)

        XCTAssertEqual(decoded.appName,  "TestApp")
        XCTAssertEqual(decoded.bundleId, "com.test.app")
        XCTAssertEqual(decoded.version,  "1.0.1")
        XCTAssertEqual(decoded.build,    "1")
        XCTAssertEqual(decoded.signingMode, "adhoc")
    }

    // Gate 2: history/<timestamp>.json is written alongside latest
    func test_gate2_writesHistoryJson() throws {
        let fs = InMemoryFileSystem()
        let writer = ReleaseManifestWriter(fs: fs)

        try writer.write(
            makeManifest(version: "1.0.0", build: "1"),
            releasesDir: "/proj/dist/releases"
        )

        let historyFiles = try fs.listDirectory(at: "/proj/dist/releases/history")
        XCTAssertEqual(historyFiles.count, 1)
        XCTAssertTrue(historyFiles[0].hasSuffix(".json"))
    }

    // Gate 3: second release overwrites latest, history has 2 entries
    func test_gate3_secondReleaseOverwritesLatestAndAppendsHistory() throws {
        let fs = InMemoryFileSystem()
        let writer = ReleaseManifestWriter(fs: fs)

        try writer.write(
            makeManifest(version: "1.0.0", build: "1", timestamp: "2026-04-11T10:00:00Z"),
            releasesDir: "/proj/dist/releases"
        )
        try writer.write(
            makeManifest(version: "1.0.1", build: "1", timestamp: "2026-04-11T10:05:00Z"),
            releasesDir: "/proj/dist/releases"
        )

        // latest should be 1.0.1
        let raw = try fs.readUTF8(at: "/proj/dist/releases/latest.json")
        XCTAssertTrue(raw.contains("1.0.1"))

        // history should have 2 entries
        let historyFiles = try fs.listDirectory(at: "/proj/dist/releases/history")
        XCTAssertEqual(historyFiles.count, 2)
    }

    // Gate 4: dry-run pipeline does NOT write manifest (tested in ReleasePipelineTests)
    // — this test verifies the writer itself is never called from dry-run context
    // The actual dry-run gate is test_c5_gate8 in ReleasePipelineTests.

    // MARK: - helpers

    private func makeManifest(
        version: String,
        build: String,
        timestamp: String = "2026-04-11T10:00:00Z"
    ) -> ReleaseManifest {
        ReleaseManifest(
            appName: "TestApp",
            bundleId: "com.test.app",
            version: version,
            build: build,
            bundlePath: "/proj/dist/TestApp.app",
            installPath: "/Applications/TestApp.app",
            backupPath: nil,
            signingMode: "adhoc",
            launchedAfterInstall: false,
            timestamp: timestamp
        )
    }
}
