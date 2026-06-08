import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct DMGCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "dmg",
        abstract: "Package the current .app into a DMG using dmgbuild."
    )

    @Flag(name: .shortAndLong, help: "Show subprocess output.")
    public var verbose: Bool = false

    @OptionGroup public var global: GlobalOptions

    public init() {}

    public func run() throws {
        let root = FileManager.default.currentDirectoryPath
        let lock = try acquireProjectLock(command: "dmg", projectRoot: root, json: global.isJSON)
        defer { lock.release(projectRoot: root) }
        let fs = RealFileSystem()
        let specPath = root + "/relios.toml"

        let spec: ReleaseSpec
        do {
            spec = try SpecLoader(fs: fs).load(from: specPath)
        } catch let error as SpecLoadError {
            if global.isJSON {
                Report.failure(command: "dmg", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[dmg] failed")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        // Version is a nice-to-have for the filename; failing to read it
        // is non-fatal — we just fall back to `<AppName>.dmg`.
        let version: String? = {
            let sourcePath = root + "/" + spec.version.sourceFile
            guard fs.fileExists(at: sourcePath) else { return nil }
            let reader = VersionSourceReader(fs: fs)
            let parsed = try? reader.read(spec: spec.version, at: sourcePath)
            return parsed.map { "\($0.version.major).\($0.version.minor).\($0.version.patch)" }
        }()

        let builder = DMGBuilder(fs: fs, process: RealProcessRunner())
        let output: DMGBuilder.Output
        do {
            output = try builder.run(
                spec: spec,
                projectRoot: root,
                version: version
            )
        } catch let error as DMGError {
            if global.isJSON {
                Report.failure(command: "dmg", code: error.code,
                               reason: error.shortReason, fix: error.shortFix)
            } else {
                print("[dmg] failed")
                print("  Reason: \(error.shortReason)")
                print("  Fix: \(error.shortFix)")
            }
            throw ExitCode.failure
        }

        if global.isJSON {
            Report.success(command: "dmg", data: output)
            return
        }

        print("✓ Created \(relativePath(output.dmgPath, root: root))")
    }

    private func relativePath(_ abs: String, root: String) -> String {
        let prefix = root + "/"
        if abs.hasPrefix(prefix) {
            return String(abs.dropFirst(prefix.count))
        }
        return abs
    }
}
