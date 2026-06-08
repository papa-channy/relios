import ArgumentParser
import Foundation
import ReliosCore
import ReliosSupport

public struct SigningCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "signing",
        abstract: "Inspect, configure, and verify Apple Developer ID signing.",
        subcommands: [
            StatusSubcommand.self,
            SetupSubcommand.self,
            ImportSubcommand.self,
            VerifySubcommand.self,
        ]
    )

    public init() {}

    // MARK: - status

    public struct StatusSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show keychain code-signing identities and relios.toml state."
        )

        @OptionGroup public var global: GlobalOptions

        public init() {}

        struct StatusPayload: Encodable {
            let identities: [KeychainIdentity]
            let mode: String?
            let identity: String?
            let teamId: String?
            let hardenedRuntime: Bool?
            let entitlements: String?

            private enum CodingKeys: String, CodingKey {
                case identities
                case mode
                case identity
                case teamId = "team_id"
                case hardenedRuntime = "hardened_runtime"
                case entitlements
            }
        }

        public func run() throws {
            let process = RealProcessRunner()
            let lister = KeychainIdentityLister(process: process)
            let identities: [KeychainIdentity]
            do {
                identities = try lister.list()
            } catch {
                if global.isJSON {
                    Report.failure(command: "signing status",
                                   code: DiagnosticCode("SIGNING_KEYCHAIN_QUERY_FAILED"),
                                   reason: "Could not query keychain: \(error)",
                                   fix: "Ensure the `security` tool is available and the keychain is unlocked")
                } else {
                    print("Could not query keychain: \(error)")
                }
                throw ExitCode.failure
            }

            if global.isJSON {
                let spec = try? loadSpec()
                let s = spec?.signing
                Report.success(command: "signing status", data: StatusPayload(
                    identities: identities,
                    mode: s?.mode.rawValue,
                    identity: s?.identity,
                    teamId: s?.teamID,
                    hardenedRuntime: s?.hardenedRuntime,
                    entitlements: s?.entitlementsPath
                ))
                return
            }

            print("Keychain identities (codesigning):")
            if identities.isEmpty {
                print("  (none — run `relios signing import <path.p12>` or install via Xcode)")
            } else {
                for id in identities {
                    let team = id.teamID.map { " team=\($0)" } ?? ""
                    print("  • \(id.name)\(team)")
                }
            }

            print("")
            if let spec = try? loadSpec() {
                let s = spec.signing
                print("relios.toml [signing]:")
                print("  mode             = \(s.mode.rawValue)")
                print("  identity         = \(s.identity ?? "(unset)")")
                print("  team_id          = \(s.teamID ?? "(unset)")")
                print("  hardened_runtime = \(s.hardenedRuntime)")
                print("  entitlements     = \(s.entitlementsPath ?? "(none)")")

                if s.mode == .developerID,
                   let name = s.identity,
                   !identities.contains(where: { $0.name == name }) {
                    print("")
                    print("⚠ identity in relios.toml is not present in the keychain.")
                }
            } else {
                print("relios.toml not found (run `relios init` first).")
            }
        }
    }

    // MARK: - setup

    public struct SetupSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "setup",
            abstract: "Configure [signing] in relios.toml for Developer ID signing."
        )

        @Option(name: .long, help: "Codesigning identity name (e.g. \"Developer ID Application: Name (TEAM123456)\").")
        public var identity: String?

        @Option(name: .customLong("team-id"), help: "10-character Apple Team ID.")
        public var teamId: String?

        @Flag(inversion: .prefixedNo, help: "Enable hardened runtime (default: enabled).")
        public var hardenedRuntime: Bool = true

        @Option(name: .long, help: "Path to an entitlements plist (optional).")
        public var entitlements: String?

        @Flag(name: .long, help: "Fail instead of prompting when required fields are missing.")
        public var nonInteractive: Bool = false

        @OptionGroup public var global: GlobalOptions

        public init() {}

        struct SetupPayload: Encodable {
            let mode: String
            let identity: String
            let teamId: String

            private enum CodingKeys: String, CodingKey {
                case mode
                case identity
                case teamId = "team_id"
            }
        }

        public func run() throws {
            let root = FileManager.default.currentDirectoryPath
            let lock = try acquireProjectLock(command: "signing setup", projectRoot: root, json: global.isJSON)
            defer { lock.release(projectRoot: root) }
            let tomlPath = root + "/relios.toml"
            let fs = RealFileSystem()
            guard fs.fileExists(at: tomlPath) else {
                if global.isJSON {
                    Report.failure(command: "signing setup", code: DiagnosticCode("SPEC_NOT_FOUND"),
                                   reason: "relios.toml not found at \(tomlPath)",
                                   fix: "Run `relios init` first.")
                } else {
                    print("relios.toml not found at \(tomlPath). Run `relios init` first.")
                }
                throw ExitCode.failure
            }

            let process = RealProcessRunner()
            let identities = (try? KeychainIdentityLister(process: process).list()) ?? []

            let (resolvedIdentity, resolvedTeam) = try resolveIdentity(
                identities: identities
            )
            let finalTeam = try resolvedTeam ?? parseOrPrompt(from: resolvedIdentity)

            let values = SigningSectionPatcher.Values(
                mode: .developerID,
                identity: resolvedIdentity,
                teamID: finalTeam,
                hardenedRuntime: hardenedRuntime,
                entitlementsPath: entitlements
            )

            let original = try fs.readUTF8(at: tomlPath)
            let patched = SigningSectionPatcher().patch(original, with: values)
            try fs.writeUTF8(patched, to: tomlPath)

            if global.isJSON {
                Report.success(command: "signing setup", data: SetupPayload(
                    mode: "developer-id",
                    identity: resolvedIdentity,
                    teamId: finalTeam
                ))
                return
            }

            print("✓ Updated \(tomlPath)")
            print("  mode     = developer-id")
            print("  identity = \(resolvedIdentity)")
            print("  team_id  = \(finalTeam)")
            if !identities.contains(where: { $0.name == resolvedIdentity }) {
                print("")
                print("⚠ identity is not in the keychain yet.")
                print("  Import it with: relios signing import <path.p12>")
            }
        }

        /// Emitted whenever JSON mode would otherwise need to read from stdin.
        private func failNeedsInput() {
            Report.failure(command: "signing setup",
                           code: DiagnosticCode("SIGNING_SETUP_NEEDS_INPUT"),
                           reason: "interactive input required in --format json",
                           fix: "pass --identity (and --team-id) or --non-interactive")
        }

        /// Resolves (identity, teamID) from flags, interactive prompt, or keychain.
        private func resolveIdentity(identities: [KeychainIdentity]) throws -> (String, String?) {
            if let provided = identity {
                let parsedTeam = KeychainIdentity.parseTeamID(from: provided)
                if let flagTeam = teamId,
                   let parsedTeam,
                   flagTeam != parsedTeam {
                    if global.isJSON {
                        Report.failure(command: "signing setup", code: DiagnosticCode("SIGNING_TEAM_ID_MISMATCH"),
                                       reason: "--team-id (\(flagTeam)) does not match team in identity (\(parsedTeam))",
                                       fix: "Pass a --team-id that matches the identity, or omit it")
                    } else {
                        print("Error: --team-id (\(flagTeam)) does not match team in identity (\(parsedTeam))")
                    }
                    throw ExitCode.failure
                }
                return (provided, teamId ?? parsedTeam)
            }

            // No --identity. JSON mode must never prompt on stdin.
            if global.isJSON {
                failNeedsInput()
                throw ExitCode.failure
            }

            if nonInteractive {
                print("Error: --identity required in --non-interactive mode.")
                throw ExitCode.failure
            }

            return try promptForIdentity(identities: identities)
        }

        private func promptForIdentity(
            identities: [KeychainIdentity]
        ) throws -> (String, String?) {
            let candidates = identities.filter {
                $0.name.contains("Developer ID Application")
            }
            guard !candidates.isEmpty else {
                print("No \"Developer ID Application\" identity in the keychain.")
                print("Options:")
                print("  • Import a .p12:   relios signing import <path.p12>")
                print("  • Install via Xcode → Settings → Accounts → Manage Certificates")
                throw ExitCode.failure
            }

            if candidates.count == 1 {
                let only = candidates[0]
                print("Using the only Developer ID Application identity in your keychain:")
                print("  \(only.name)")
                return (only.name, only.teamID)
            }

            print("Choose an identity:")
            for (i, id) in candidates.enumerated() {
                print("  [\(i + 1)] \(id.name)")
            }
            print("Enter number: ", terminator: "")
            guard let input = readLine(strippingNewline: true),
                  let idx = Int(input),
                  (1...candidates.count).contains(idx) else {
                print("Invalid selection.")
                throw ExitCode.failure
            }
            let picked = candidates[idx - 1]
            return (picked.name, picked.teamID)
        }

        private func parseOrPrompt(from identity: String) throws -> String {
            if let parsed = KeychainIdentity.parseTeamID(from: identity) {
                return parsed
            }
            // Cannot parse a team_id and none was supplied: JSON mode must not prompt.
            if global.isJSON {
                failNeedsInput()
                throw ExitCode.failure
            }
            if nonInteractive {
                print("Error: could not parse team_id from identity; pass --team-id.")
                throw ExitCode.failure
            }
            print("Team ID not found in identity string. Enter Team ID (10 chars): ", terminator: "")
            guard let input = readLine(strippingNewline: true),
                  input.count == 10 else {
                print("Invalid Team ID.")
                throw ExitCode.failure
            }
            return input
        }
    }

    // MARK: - import

    public struct ImportSubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "import",
            abstract: "Import a .p12 certificate into a macOS keychain."
        )

        @Argument(help: "Path to the .p12 file.")
        public var p12Path: String

        @Option(name: .long, help: "Keychain to import into (default: login).")
        public var keychain: String = "login.keychain-db"

        @Option(name: .long, help: "Env var that holds the .p12 password.")
        public var passwordEnv: String = "RELIOS_CERT_PASSWORD"

        @OptionGroup public var global: GlobalOptions

        public init() {}

        struct ImportPayload: Encodable {
            let importedPath: String
            let keychain: String

            private enum CodingKeys: String, CodingKey {
                case importedPath = "imported_path"
                case keychain
            }
        }

        public func run() throws {
            guard FileManager.default.fileExists(atPath: p12Path) else {
                if global.isJSON {
                    Report.failure(command: "signing import", code: DiagnosticCode("SIGNING_P12_NOT_FOUND"),
                                   reason: "File not found: \(p12Path)",
                                   fix: "Pass a valid path to a .p12 certificate file")
                } else {
                    print("File not found: \(p12Path)")
                }
                throw ExitCode.failure
            }
            guard let password = ProcessInfo.processInfo.environment[passwordEnv],
                  !password.isEmpty else {
                if global.isJSON {
                    Report.failure(command: "signing import", code: DiagnosticCode("SIGNING_CERT_PASSWORD_MISSING"),
                                   reason: "env var \(passwordEnv) is empty or unset",
                                   fix: "Set it first: export \(passwordEnv)='...'")
                } else {
                    print("Error: env var \(passwordEnv) is empty or unset.")
                    print("Set it first:   export \(passwordEnv)='...'")
                }
                throw ExitCode.failure
            }

            let process = RealProcessRunner()
            // -T /usr/bin/codesign grants codesign access without further prompts.
            let command = "security import '\(p12Path)' -k \(keychain) -P '\(password)' -T /usr/bin/codesign"
            let result: ProcessResult
            do {
                result = try process.runShell(command, cwd: nil)
            } catch {
                if global.isJSON {
                    Report.failure(command: "signing import", code: DiagnosticCode("SIGNING_IMPORT_FAILED"),
                                   reason: "Failed to run `security import`: \(error)",
                                   fix: "Ensure the `security` tool is available")
                } else {
                    print("Failed to run `security import`: \(error)")
                }
                throw ExitCode.failure
            }
            guard result.exitCode == 0 else {
                if global.isJSON {
                    Report.failure(command: "signing import", code: DiagnosticCode("SIGNING_IMPORT_FAILED"),
                                   reason: "security import failed (exit \(result.exitCode))",
                                   fix: "Check the .p12 password and that the keychain exists",
                                   detail: result.stderr.isEmpty ? nil : result.stderr)
                } else {
                    print("security import failed (exit \(result.exitCode))")
                    if !result.stderr.isEmpty { print(result.stderr) }
                }
                throw ExitCode.failure
            }

            if global.isJSON {
                Report.success(command: "signing import", data: ImportPayload(
                    importedPath: p12Path, keychain: keychain
                ))
                return
            }

            print("✓ Imported \(p12Path) into \(keychain)")
            print("Next: run `relios signing status` to verify, then `relios signing setup`.")
        }
    }

    // MARK: - verify

    public struct VerifySubcommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Run codesign --verify and show signature details for an .app."
        )

        @Argument(help: "Path to a .app bundle. Defaults to [bundle].output_path from relios.toml.")
        public var appPath: String?

        @OptionGroup public var global: GlobalOptions

        public init() {}

        struct VerifyPayload: Encodable {
            let appPath: String
            let valid: Bool

            private enum CodingKeys: String, CodingKey {
                case appPath = "app_path"
                case valid
            }
        }

        public func run() throws {
            let path: String
            do {
                path = try resolvePath()
            } catch let error as SpecLoadError {
                if global.isJSON {
                    Report.failure(command: "signing verify", code: error.code,
                                   reason: error.shortReason, fix: error.shortFix)
                    throw ExitCode.failure
                }
                throw error
            }
            let process = RealProcessRunner()

            let verify = try process.runShell("codesign --verify --deep --strict --verbose=2 '\(path)'", cwd: nil)
            let display = try process.runShell("codesign -dv --verbose=4 '\(path)'", cwd: nil)

            // The codesign dumps would corrupt the single JSON object on stdout.
            if !global.isJSON {
                print("--- codesign --verify ---")
                if !verify.stdout.isEmpty { print(verify.stdout) }
                if !verify.stderr.isEmpty { print(verify.stderr) }

                print("--- codesign -dv ---")
                if !display.stderr.isEmpty { print(display.stderr) }
                if !display.stdout.isEmpty { print(display.stdout) }
            }

            if verify.exitCode != 0 {
                if global.isJSON {
                    let tail = verify.stderr.isEmpty ? verify.stdout : verify.stderr
                    Report.failure(command: "signing verify", code: DiagnosticCode("SIGNING_VERIFY_FAILED"),
                                   reason: "codesign --verify failed (exit \(verify.exitCode))",
                                   fix: "Sign the app with a valid Developer ID cert and re-verify",
                                   detail: tail.isEmpty ? nil : tail)
                }
                throw ExitCode.failure
            }

            if global.isJSON {
                Report.success(command: "signing verify", data: VerifyPayload(appPath: path, valid: true))
            }
        }

        private func resolvePath() throws -> String {
            if let appPath { return appPath }
            let spec = try loadSpec()
            let root = FileManager.default.currentDirectoryPath
            return root + "/" + spec.bundle.outputPath
        }
    }
}

// MARK: - shared helpers

private func loadSpec() throws -> ReleaseSpec {
    let root = FileManager.default.currentDirectoryPath
    return try SpecLoader(fs: RealFileSystem()).load(from: root + "/relios.toml")
}
