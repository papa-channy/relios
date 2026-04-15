import Foundation
import ReliosSupport

/// Scans a project directory and reports just enough to seed a `SpecSkeleton`.
///
/// Detects two project types:
/// - **SwiftPM**: `Package.swift` present, no Xcode markers → `.swiftpm`
/// - **Xcode**: `.xcodeproj`, `.xcworkspace`, or `project.yml` present → `.xcodebuild`
///
/// **Init must never crash.** Every "could not detect" branch falls back
/// rather than throwing; the only thrown error is `notRecognizedProject`,
/// which means neither Package.swift nor any Xcode marker was found.
public struct ProjectScanner: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func scan(root: String) throws -> ProjectScanResult {
        let xcodeMarkers = XcodeProjectGuardRule.detectXcodeMarkers(root: root, fs: fs)
        let hasPackageSwift = fs.fileExists(at: root + "/Package.swift")

        // Xcode project detected → xcodebuild type
        if !xcodeMarkers.isEmpty {
            let target = detectSchemeName(root: root, markers: xcodeMarkers)
            return ProjectScanResult(
                root: root,
                projectType: .xcodebuild,
                binaryTarget: target
            )
        }

        // Pure SwiftPM
        if hasPackageSwift {
            let target = detectBinaryTarget(root: root)
            return ProjectScanResult(
                root: root,
                projectType: .swiftpm,
                binaryTarget: target
            )
        }

        // Neither
        throw InitError.notSwiftPMProject(root: root)
    }

    // MARK: - private

    /// For Xcode projects, attempts to derive the scheme/target name from
    /// the .xcodeproj filename (e.g. `MyApp.xcodeproj` → `MyApp`).
    /// Falls back to the project root directory basename.
    private func detectSchemeName(root: String, markers: [String]) -> String {
        let fallback = URL(fileURLWithPath: root).lastPathComponent
        // Try .xcodeproj name first — most reliable heuristic
        for marker in markers {
            if marker.hasSuffix(".xcodeproj") {
                let name = (marker as NSString).deletingPathExtension
                if !name.isEmpty { return name }
            }
        }
        return fallback
    }

    /// Looks for `Sources/<Name>/<Name>.swift`. Returns the first match by
    /// alphabetical order so behavior is deterministic across runs.
    /// Falls back to the project root's basename on any miss.
    private func detectBinaryTarget(root: String) -> String {
        let fallback = URL(fileURLWithPath: root).lastPathComponent
        let sourcesPath = root + "/Sources"

        guard fs.isDirectory(at: sourcesPath) else {
            return fallback
        }

        let candidates: [String]
        do {
            candidates = try fs.listDirectory(at: sourcesPath).sorted()
        } catch {
            return fallback
        }

        // First pass: prefer a target directory that has <Name>.swift
        // (tightest match — rules out test dirs, resource-only dirs, etc.).
        for name in candidates {
            let dir = sourcesPath + "/" + name
            guard fs.isDirectory(at: dir) else { continue }

            let mainFile = dir + "/" + name + ".swift"
            if fs.fileExists(at: mainFile) {
                return name
            }
        }

        // Second pass: if Sources/ has exactly one subdirectory with any
        // .swift file, use its name. Catches projects like WorkspaceLauncher
        // where the entry point is `App.swift` (SwiftUI `@main`) rather
        // than `WorkspaceLauncher.swift`. Multi-target projects fall
        // through to the root-basename fallback to stay deterministic.
        let targetDirs = candidates.filter { name in
            let dir = sourcesPath + "/" + name
            guard fs.isDirectory(at: dir) else { return false }
            let entries = (try? fs.listDirectory(at: dir)) ?? []
            return entries.contains(where: { $0.hasSuffix(".swift") })
        }
        if targetDirs.count == 1 {
            return targetDirs[0]
        }

        return fallback
    }
}
