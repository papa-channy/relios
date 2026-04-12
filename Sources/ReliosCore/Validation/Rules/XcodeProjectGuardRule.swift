import ReliosSupport

/// Fails if the project root contains Xcode project markers
/// (.xcodeproj, .xcworkspace, project.yml) while `[bundle].mode`
/// is `assembly`.
///
/// Relios bundle assembly builds a .app from scratch — this is
/// incompatible with Xcode/XcodeGen projects where `xcodebuild`
/// already produces a complete .app. In passthrough mode the .app
/// is accepted as-is, so Xcode markers are fine.
public struct XcodeProjectGuardRule: ValidationRule {
    public init() {}

    public func evaluate(_ context: ValidationContext) -> RuleResult {
        let root = context.projectRoot
        let markers = Self.detectXcodeMarkers(root: root, fs: context.fs)

        if markers.isEmpty {
            return .ok(title: "project type compatible")
        }

        // Passthrough mode explicitly opts in to the "xcodebuild → Relios
        // handles the rest" workflow, so Xcode markers are expected.
        if context.spec.bundle.mode == .passthrough {
            return .ok(title: "project type compatible (passthrough)")
        }

        return .fail(
            title: "Xcode project detected with assembly mode",
            reason: "Found \(markers.joined(separator: ", ")) — Relios bundle assembly is incompatible with Xcode-managed projects",
            fix: "Set [bundle].mode = \"passthrough\" and [project].type = \"xcodebuild\" in relios.toml, or remove Xcode project files for pure SwiftPM."
        )
    }

    // MARK: - internal (shared with ProjectScanner)

    static func detectXcodeMarkers(root: String, fs: any FileSystem) -> [String] {
        var found: [String] = []

        // project.yml (XcodeGen)
        if fs.fileExists(at: root + "/project.yml") {
            found.append("project.yml")
        }

        // .xcodeproj / .xcworkspace
        guard let entries = try? fs.listDirectory(at: root) else {
            return found
        }

        for entry in entries.sorted() {
            if entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace") {
                found.append(entry)
            }
        }

        return found
    }
}
