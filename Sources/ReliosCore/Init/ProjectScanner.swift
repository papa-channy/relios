import Foundation
import ReliosSupport

/// Scans a project directory and reports just enough to seed a `SpecSkeleton`.
///
/// v1 is intentionally a "80% heuristic" — it does NOT parse Package.swift,
/// does NOT walk multi-target manifests, and does NOT read Swift source. It
/// looks for `Package.swift` and the SwiftPM-default `Sources/<Name>/<Name>.swift`
/// pattern, and falls back to the directory basename if either is missing.
///
/// **Init must never crash.** Every "could not detect" branch falls back
/// rather than throwing; the only thrown error is `notSwiftPMProject`,
/// which is a pre-condition (no Package.swift means relios isn't applicable).
public struct ProjectScanner: Sendable {
    private let fs: any FileSystem

    public init(fs: any FileSystem) {
        self.fs = fs
    }

    public func scan(root: String) throws -> ProjectScanResult {
        guard fs.fileExists(at: root + "/Package.swift") else {
            throw InitError.notSwiftPMProject(root: root)
        }

        let target = detectBinaryTarget(root: root)

        return ProjectScanResult(
            root: root,
            projectType: .swiftpm,
            binaryTarget: target
        )
    }

    // MARK: - private

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

        for name in candidates {
            let dir = sourcesPath + "/" + name
            guard fs.isDirectory(at: dir) else { continue }

            let mainFile = dir + "/" + name + ".swift"
            if fs.fileExists(at: mainFile) {
                return name
            }
        }

        return fallback
    }
}
