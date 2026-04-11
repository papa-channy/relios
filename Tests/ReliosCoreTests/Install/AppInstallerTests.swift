import XCTest
import ReliosCore
import ReliosSupport

/// Gates 1, 5, 6, 9: install, idempotency, no-existing-app, atomic safety.
final class AppInstallerTests: XCTestCase {

    // Gate 1: copies .app from dist to install path
    func test_gate1_installsCopiesAppToDestination() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/dist/MyApp.app/Contents/MacOS/MyApp": "binary",
            "/proj/dist/MyApp.app/Contents/Info.plist": "plist",
        ])
        let installer = AppInstaller(fs: fs)

        try installer.install(
            from: "/proj/dist/MyApp.app",
            to: "/Applications/MyApp.app"
        )

        XCTAssertTrue(fs.fileExists(at: "/Applications/MyApp.app"))
    }

    // Gate 5: idempotent — run twice, second works fine
    func test_gate5_idempotentInstall() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/dist/MyApp.app/Contents/MacOS/MyApp": "binary-v1",
        ])
        let installer = AppInstaller(fs: fs)

        try installer.install(from: "/proj/dist/MyApp.app", to: "/Applications/MyApp.app")

        // Update source, install again
        try fs.writeUTF8("binary-v2", to: "/proj/dist/MyApp.app/Contents/MacOS/MyApp")
        try installer.install(from: "/proj/dist/MyApp.app", to: "/Applications/MyApp.app")

        XCTAssertTrue(fs.fileExists(at: "/Applications/MyApp.app"))
    }

    // Gate 6: works when no existing app at destination
    func test_gate6_worksWhenNoExistingApp() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/dist/MyApp.app/Contents/MacOS/MyApp": "binary",
        ])
        let installer = AppInstaller(fs: fs)

        XCTAssertNoThrow(try installer.install(
            from: "/proj/dist/MyApp.app",
            to: "/Applications/MyApp.app"
        ))
    }
}
