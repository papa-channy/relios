import Foundation
import ReliosSupport

/// Orchestrates DMG creation via the `dmgbuild` Python tool.
///
/// Steps:
///   1. Verify the `.app` bundle exists.
///   2. Ensure `[dmg].output_dir` exists; purge any pre-existing `*.dmg`
///      (guide's Problem 4: stale Tauri-generated DMGs confuse things —
///      Relios has the same risk if the user invokes `dmg` repeatedly).
///   3. Synthesize `dmg-settings.py` into a temp file under `output_dir`.
///   4. Shell out to `dmgbuild` with `DMGBUILD_APP_PATH` env var.
///   5. Remove the temp settings file on success and on failure.
///
/// Inputs are read from the `[dmg]` section and `[bundle].output_path`.
public struct DMGBuilder: Sendable {
    public struct Output: Equatable, Sendable {
        public let dmgPath: String
    }

    private let fs: any FileSystem
    private let process: any ProcessRunner

    public init(fs: any FileSystem, process: any ProcessRunner) {
        self.fs = fs
        self.process = process
    }

    public func run(
        spec: ReleaseSpec,
        projectRoot: String,
        version: String?
    ) throws -> Output {
        guard let dmg = spec.dmg, dmg.enabled else {
            throw DMGError.disabled
        }

        let appPath = absolute(spec.bundle.outputPath, relativeTo: projectRoot)
        guard fs.fileExists(at: appPath) else {
            throw DMGError.appMissing(path: appPath)
        }

        let outputDir = absolute(dmg.outputDir, relativeTo: projectRoot)
        try ensureDir(outputDir)
        try purgeExistingDMGs(in: outputDir)

        let appBundleName = (appPath as NSString).lastPathComponent       // MyApp.app
        let baseName      = (appBundleName as NSString).deletingPathExtension // MyApp
        let volumeName    = dmg.volumeName ?? baseName

        let filename: String
        if let version, !version.isEmpty {
            filename = "\(baseName)-\(version).dmg"
        } else {
            filename = "\(baseName).dmg"
        }
        let dmgPath = outputDir + "/" + filename

        let settingsPath = outputDir + "/_dmg-settings.py"
        let settings = DMGSettingsRenderer().render(dmg, appBundleName: appBundleName)
        try write(settings, to: settingsPath)
        defer { try? fs.removeItem(at: settingsPath) }

        // `command -v dmgbuild` so the shell reports exactly what we'll invoke.
        let check = try process.runShell("command -v dmgbuild", cwd: nil)
        guard check.exitCode == 0 else {
            throw DMGError.dmgbuildNotFound
        }

        // Single-line command; dmgbuild reads the settings file and writes
        // the .dmg. We set DMGBUILD_APP_PATH so settings.py can pick up the
        // .app location without hardcoding it.
        let cmd = """
        DMGBUILD_APP_PATH=\(shellQuote(appPath)) dmgbuild \
        -s \(shellQuote(settingsPath)) \
        \(shellQuote(volumeName)) \
        \(shellQuote(dmgPath))
        """
        let result = try process.runShell(cmd, cwd: projectRoot)
        guard result.exitCode == 0 else {
            throw DMGError.dmgbuildFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return Output(dmgPath: dmgPath)
    }

    // MARK: - private

    private func ensureDir(_ path: String) throws {
        if fs.isDirectory(at: path) { return }
        do {
            try fs.createDirectory(at: path)
        } catch {
            throw DMGError.writeFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }

    private func purgeExistingDMGs(in dir: String) throws {
        let entries = (try? fs.listDirectory(at: dir)) ?? []
        for name in entries where name.hasSuffix(".dmg") {
            try? fs.removeItem(at: dir + "/" + name)
        }
    }

    private func write(_ content: String, to path: String) throws {
        do {
            try fs.writeUTF8(content, to: path)
        } catch {
            throw DMGError.writeFailed(
                path: path,
                underlying: String(describing: error)
            )
        }
    }

    private func absolute(_ path: String, relativeTo root: String) -> String {
        if path.hasPrefix("/") { return path }
        return root + "/" + path
    }

    private func shellQuote(_ s: String) -> String {
        // Single-quote and escape embedded single quotes the POSIX way.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
