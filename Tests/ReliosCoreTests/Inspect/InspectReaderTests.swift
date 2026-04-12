import XCTest
import Foundation
import ReliosCore
import ReliosSupport

/// Gates 5-6: inspect reads latest.json, handles missing file.
final class InspectReaderTests: XCTestCase {

    // Gate 5: reads latest.json and returns correct manifest
    func test_gate5_readsLatestManifest() throws {
        let manifest = ReleaseManifest(
            appName: "TestApp",
            bundleId: "com.test.app",
            version: "1.0.1",
            build: "1",
            bundlePath: "/proj/dist/TestApp.app",
            installPath: "/Applications/TestApp.app",
            backupPath: nil,
            signingMode: "adhoc",
            bundleMode: "assembly",
            launchedAfterInstall: true,
            timestamp: "2026-04-11T10:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let json = String(data: data, encoding: .utf8)!

        let fs = InMemoryFileSystem(files: [
            "/proj/dist/releases/latest.json": json,
        ])
        let reader = InspectReader(fs: fs)
        let result = try reader.readLatest(releasesDir: "/proj/dist/releases")

        XCTAssertEqual(result.appName, "TestApp")
        XCTAssertEqual(result.version, "1.0.1")
        XCTAssertEqual(result.build,   "1")
        XCTAssertEqual(result.signingMode, "adhoc")
        XCTAssertTrue(result.launchedAfterInstall)
    }

    // Gate 6: missing latest.json → ManifestError.latestNotFound
    func test_gate6_throwsWhenLatestMissing() {
        let fs = InMemoryFileSystem()
        let reader = InspectReader(fs: fs)

        XCTAssertThrowsError(try reader.readLatest(releasesDir: "/proj/dist/releases")) { error in
            guard let e = error as? ManifestError else { return XCTFail("wrong type") }
            if case .latestNotFound = e { /* ok */ } else {
                XCTFail("expected .latestNotFound, got \(e)")
            }
        }
    }
}
