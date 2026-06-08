import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct UpdateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Generate the auto-update feed (update.json) the shipped app polls.",
        subcommands: [GenerateSubcommand.self, KeygenSubcommand.self],
        defaultSubcommand: GenerateSubcommand.self
    )

    public init() {}

    public struct GenerateSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "generate",
            abstract: "Write the update manifest for the current version."
        )

        @Option(name: .long, help: "Release tag this manifest describes, e.g. v2.0.1.")
        public var tag: String

        @Option(name: .long, help: "GitHub repo as owner/repo (for the download/notes URL template).")
        public var repo: String?

        @Option(name: .long, help: "Artifact filename for the download URL template, e.g. MyApp-2.0.1.dmg.")
        public var asset: String?

        @Option(name: .long, help: "Explicit artifact download URL (overrides the template).")
        public var downloadURL: String?

        @Option(name: .long, help: "Release notes text.")
        public var notes: String?

        @Option(name: .long, help: "Read release notes from a file.")
        public var notesFile: String?

        @Option(name: .long, help: "Explicit release-notes URL (overrides the derived release page).")
        public var notesURL: String?

        @Option(name: .long, help: "Override the output path for the manifest.")
        public var output: String?

        @Option(name: .long, help: "Local artifact file to hash (sha256 + size).")
        public var artifact: String?

        @Option(name: .long, help: "Git commit to record for provenance.")
        public var commit: String?

        @Option(name: .long, help: "Path to an Ed25519 private key file; signs the feed → <feed>.sig. Or set RELIOS_UPDATE_SIGNING_KEY (base64).")
        public var signingKeyFile: String?

        @OptionGroup public var global: GlobalOptions

        public init() {}

        public func run() throws {
            let root = FileManager.default.currentDirectoryPath
            let lock = try acquireProjectLock(command: "update generate", projectRoot: root, json: global.isJSON)
            defer { lock.release(projectRoot: root) }
            let fs = RealFileSystem()
            let specPath = root + "/relios.toml"

            let spec: ReleaseSpec
            do {
                spec = try SpecLoader(fs: fs).load(from: specPath)
            } catch let error as SpecLoadError {
                if global.isJSON {
                    Report.failure(command: "update generate", code: error.code,
                                   reason: error.shortReason, fix: error.shortFix)
                } else {
                    print("[update] failed at: spec load")
                    print("  Reason: \(error.shortReason)")
                    print("  Fix: \(error.shortFix)")
                }
                throw ExitCode.failure
            }

            // Resolve notes: --notes-file takes precedence if both are given.
            let resolvedNotes = try resolveNotes(fs: fs)
            let signingKey = try resolveSigningKey(fs: fs)

            let options = UpdateRunner.Options(
                tag: tag,
                repo: repo,
                asset: asset,
                downloadURL: downloadURL,
                notes: resolvedNotes,
                notesURL: notesURL,
                outputOverride: output,
                artifactPath: artifact,
                gitCommit: commit,
                signingKeyBase64: signingKey
            )

            let runner = UpdateRunner(fs: fs)
            let result: UpdateRunner.Result
            do {
                result = try runner.run(spec: spec, projectRoot: root, options: options)
            } catch let error as UpdateError {
                if global.isJSON {
                    Report.failure(command: "update generate", code: error.code,
                                   reason: error.shortReason, fix: error.shortFix)
                } else {
                    print("[update] failed")
                    print("  Reason: \(error.shortReason)")
                    print("  Fix: \(error.shortFix)")
                }
                throw ExitCode.failure
            }

            if global.isJSON {
                Report.success(command: "update generate", data: result)
                return
            }

            printResult(result)
        }

        // MARK: - helpers

        private func resolveNotes(fs: RealFileSystem) throws -> String? {
            if let notesFile {
                do {
                    return try fs.readUTF8(at: notesFile)
                } catch {
                    if global.isJSON {
                        Report.failure(command: "update generate",
                                       code: DiagnosticCode("UPDATE_NOTES_FILE_UNREADABLE"),
                                       reason: "Could not read notes file at \(notesFile)",
                                       fix: "Check the path passed to --notes-file")
                    } else {
                        print("[update] failed")
                        print("  Reason: Could not read notes file at \(notesFile)")
                        print("  Fix: Check the path passed to --notes-file")
                    }
                    throw ExitCode.failure
                }
            }
            return notes
        }

        /// Signing key from --signing-key-file (file contents) or the
        /// RELIOS_UPDATE_SIGNING_KEY env var (base64). Returns nil if neither.
        private func resolveSigningKey(fs: RealFileSystem) throws -> String? {
            if let file = signingKeyFile {
                do {
                    return try fs.readUTF8(at: file).trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    if global.isJSON {
                        Report.failure(command: "update generate",
                                       code: DiagnosticCode("UPDATE_SIGNING_KEY_UNREADABLE"),
                                       reason: "Could not read signing key at \(file)",
                                       fix: "Check --signing-key-file or use RELIOS_UPDATE_SIGNING_KEY")
                    } else {
                        print("[update] failed")
                        print("  Reason: Could not read signing key at \(file)")
                        print("  Fix: Check --signing-key-file or use RELIOS_UPDATE_SIGNING_KEY")
                    }
                    throw ExitCode.failure
                }
            }
            if let env = ProcessInfo.processInfo.environment["RELIOS_UPDATE_SIGNING_KEY"], !env.isEmpty {
                return env
            }
            return nil
        }

        private func printResult(_ r: UpdateRunner.Result) {
            print("✓ Wrote update manifest: \(r.manifestPath)")
            print("✓ Version: \(r.version) (build \(r.build))")
            print("✓ Download: \(r.downloadURL)")
            if let sha = r.sha256 {
                print("✓ SHA-256: \(sha)")
            }
            if let sig = r.signaturePath {
                print("✓ Signed: \(sig)")
            }
            if let feed = r.feedURL {
                print("")
                print("  Point your app's updater at: \(feed)")
            }
        }
    }

    // MARK: - keygen

    public struct KeygenSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "keygen",
            abstract: "Generate an Ed25519 keypair for signing the update feed."
        )

        @Option(name: .long, help: "Directory to write the private key into.")
        public var out: String = ".relios"

        @OptionGroup public var global: GlobalOptions

        public init() {}

        struct KeygenPayload: Encodable {
            let publicKeyBase64: String
            let privateKeyPath: String
            enum CodingKeys: String, CodingKey {
                case publicKeyBase64 = "public_key_base64"
                case privateKeyPath = "private_key_path"
            }
        }

        public func run() throws {
            let pair = FeedSigner.generateKeyPair()
            let fm = FileManager.default
            try? fm.createDirectory(atPath: out, withIntermediateDirectories: true)
            let keyPath = out + "/relios-update.key"
            do {
                try (pair.privateKeyBase64 + "\n").write(toFile: keyPath, atomically: true, encoding: .utf8)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
            } catch {
                if global.isJSON {
                    Report.failure(command: "update keygen",
                                   code: DiagnosticCode("UPDATE_KEYGEN_WRITE_FAILED"),
                                   reason: "Could not write private key to \(keyPath)",
                                   fix: "Check directory permissions or pass --out")
                } else {
                    print("[update keygen] failed")
                    print("  Reason: Could not write private key to \(keyPath)")
                }
                throw ExitCode.failure
            }

            if global.isJSON {
                Report.success(command: "update keygen",
                               data: KeygenPayload(publicKeyBase64: pair.publicKeyBase64, privateKeyPath: keyPath))
                return
            }

            print("✓ Wrote private key: \(keyPath) (keep secret — add to CI as RELIOS_UPDATE_SIGNING_KEY)")
            print("")
            print("Public key (embed in your app to verify the feed):")
            print("  \(pair.publicKeyBase64)")
        }
    }
}
