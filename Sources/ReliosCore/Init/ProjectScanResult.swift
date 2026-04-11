/// What `ProjectScanner` learned about a project from a single read-only sweep.
/// Intentionally tiny — v1 only needs enough to seed a usable `SpecSkeleton`.
public struct ProjectScanResult: Sendable, Equatable {
    public let root: String
    public let projectType: ProjectSection.Kind
    public let binaryTarget: String

    public init(root: String, projectType: ProjectSection.Kind, binaryTarget: String) {
        self.root = root
        self.projectType = projectType
        self.binaryTarget = binaryTarget
    }
}
