import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

/// Prints the project's *app* version read from the version source file —
/// distinct from `relios --version`, which reports the Relios tool version.
///
/// Scriptable by design: with no flags it prints exactly the version string
/// (e.g. `2.0.1`) so CI can do `VERSION=$(relios version)`. This is what the
/// generated auto-release workflow uses to decide whether to cut a new tag.
public struct VersionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the current app version (from the version source file)."
    )

    @Flag(name: .long, help: "Print the build number instead of the version.")
    public var build: Bool = false

    @Flag(name: .long, help: "Print both as `<version> (build <n>)`.")
    public var full: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    /// JSON payload always carries both version and build, regardless of the
    /// --build/--full flags (those only select the human one-liner output).
    struct VersionPayload: Encodable {
        let version: String
        let build: String
    }

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let fs = RealFileSystem()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "version", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                FileHandle.standardError.write(Data("[version] \(error.shortReason)\n".utf8))
            }
            throw ExitCode.failure
        }

        let reader = VersionSourceReader(fs: fs)
        let path = root + "/" + spec.version.sourceFile
        let result: (version: SemanticVersion, build: BuildNumber)
        do {
            result = try reader.read(spec: spec.version, at: path)
        } catch let error as VersionSourceError {
            if global.isJSON {
                Report.failure(command: "version", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                FileHandle.standardError.write(Data("[version] \(error.shortReason)\n".utf8))
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "version", data: VersionPayload(
                version: result.version.formatted,
                build: result.build.formatted
            ))
            return
        }

        if full {
            print("\(result.version.formatted) (build \(result.build.formatted))")
        } else if build {
            print(result.build.formatted)
        } else {
            print(result.version.formatted)
        }
    }
}
