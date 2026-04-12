import XCTest
import ReliosCore
import ReliosSupport

/// Locks the Init slice's scanner contract:
///   - missing Package.swift (no Xcode markers) → throw
///   - canonical SwiftPM layout → detect target name, type = .swiftpm
///   - Xcode markers → detect scheme name, type = .xcodebuild
///   - any "couldn't detect" branch → fall back, never crash
final class ProjectScannerTests: XCTestCase {

    func test_throwsWhenNeitherPackageSwiftNorXcodeMarkersExist() {
        let fs = InMemoryFileSystem(files: [:])
        let scanner = ProjectScanner(fs: fs)

        XCTAssertThrowsError(try scanner.scan(root: "/proj")) { error in
            guard let initError = error as? InitError else {
                XCTFail("Expected InitError, got \(type(of: error))")
                return
            }
            if case .notSwiftPMProject(let root) = initError {
                XCTAssertEqual(root, "/proj")
            } else {
                XCTFail("Expected .notSwiftPMProject, got \(initError)")
            }
        }
    }

    // MARK: - SwiftPM detection

    func test_detectsBinaryTargetFromCanonicalSwiftPMLayout() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// package manifest",
            "/proj/Sources/PortfolioManager/PortfolioManager.swift": "// main",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        XCTAssertEqual(result.root, "/proj")
        XCTAssertEqual(result.projectType, .swiftpm)
        XCTAssertEqual(result.binaryTarget, "PortfolioManager")
    }

    func test_picksFirstAlphabeticalCandidateWhenMultipleTargetsMatch() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/Package.swift": "// package manifest",
            "/proj/Sources/Beta/Beta.swift":  "// main",
            "/proj/Sources/Alpha/Alpha.swift": "// main",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        // Deterministic: alphabetically first wins.
        XCTAssertEqual(result.binaryTarget, "Alpha")
    }

    // MARK: - Xcode project detection

    func test_detectsXcodeprojAsXcodebuildType() throws {
        let fs = InMemoryFileSystem(
            files: ["/proj/Package.swift": "// manifest"],
            directories: ["/proj/MyApp.xcodeproj"]
        )
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        XCTAssertEqual(result.projectType, .xcodebuild)
        XCTAssertEqual(result.binaryTarget, "MyApp")
    }

    func test_detectsXcworkspaceAsXcodebuildType() throws {
        let fs = InMemoryFileSystem(
            files: [:],
            directories: ["/proj/MyApp.xcworkspace"]
        )
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        XCTAssertEqual(result.projectType, .xcodebuild)
    }

    func test_detectsProjectYmlAsXcodebuildType() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/project.yml": "name: MyApp",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        XCTAssertEqual(result.projectType, .xcodebuild)
    }

    func test_xcodeMarkersTakePriorityOverPackageSwift() throws {
        // Both Package.swift and .xcodeproj exist → xcodebuild wins
        let fs = InMemoryFileSystem(
            files: ["/proj/Package.swift": ""],
            directories: ["/proj/MyApp.xcodeproj"]
        )
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj")

        XCTAssertEqual(result.projectType, .xcodebuild)
        XCTAssertEqual(result.binaryTarget, "MyApp")
    }

    func test_xcodebuildFallsBackToDirectoryBasenameWhenNoXcodeproj() throws {
        // project.yml exists but no .xcodeproj → fallback to dir name
        let fs = InMemoryFileSystem(files: [
            "/proj/MyApp/project.yml": "name: MyApp",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj/MyApp")

        XCTAssertEqual(result.projectType, .xcodebuild)
        XCTAssertEqual(result.binaryTarget, "MyApp")
    }

    // MARK: - fallback

    func test_fallsBackToRootBasenameWhenSourcesDirectoryIsMissing() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/MyApp/Package.swift": "// package manifest",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj/MyApp")

        XCTAssertEqual(result.binaryTarget, "MyApp")
    }

    func test_fallsBackToRootBasenameWhenNoFolderMatchesNamingConvention() throws {
        // Sources/ exists, has subfolders, but none contain `<Name>.swift`.
        let fs = InMemoryFileSystem(files: [
            "/proj/MyApp/Package.swift": "// package manifest",
            "/proj/MyApp/Sources/Foo/Helper.swift": "// not a main",
            "/proj/MyApp/Sources/Bar/Util.swift":   "// not a main",
        ])
        let scanner = ProjectScanner(fs: fs)

        let result = try scanner.scan(root: "/proj/MyApp")

        XCTAssertEqual(result.binaryTarget, "MyApp")
    }
}
