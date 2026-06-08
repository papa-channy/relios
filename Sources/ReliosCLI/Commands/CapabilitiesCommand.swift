import ArgumentParser
import Foundation
import ReliosCore

/// Agent bootstrap handshake: reports the CLI version, the JSON output schema
/// version, and per-command capability flags so an agent can confirm it is
/// talking to a compatible Relios before issuing mutating commands.
public struct CapabilitiesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "capabilities",
        abstract: "Print CLI capabilities (version, output schema, per-command flags)."
    )

    @OptionGroup public var global: GlobalOptions

    public init() {}

    struct CommandCapability: Encodable {
        let name: String
        let implemented: Bool
        let dryRun: Bool
        let mutating: Bool

        enum CodingKeys: String, CodingKey {
            case name, implemented
            case dryRun = "dry_run"
            case mutating
        }
    }

    struct Payload: Encodable {
        let cliVersion: String
        let schemaVersion: Int
        let commands: [CommandCapability]

        enum CodingKeys: String, CodingKey {
            case cliVersion = "cli_version"
            case schemaVersion = "schema_version"
            case commands
        }
    }

    // name → (implemented, dryRun, mutating)
    private static let registry: [CommandCapability] = [
        .init(name: "init",         implemented: true,  dryRun: false, mutating: true),
        .init(name: "doctor",       implemented: true,  dryRun: false, mutating: false),
        .init(name: "build",        implemented: true,  dryRun: false, mutating: false),
        .init(name: "release",      implemented: true,  dryRun: true,  mutating: true),
        .init(name: "install",      implemented: true,  dryRun: false, mutating: true),
        .init(name: "open",         implemented: true,  dryRun: false, mutating: false),
        .init(name: "inspect",      implemented: true,  dryRun: false, mutating: false),
        .init(name: "rollback",     implemented: true,  dryRun: false, mutating: true),
        .init(name: "version",      implemented: true,  dryRun: false, mutating: false),
        .init(name: "signing",      implemented: true,  dryRun: false, mutating: true),
        .init(name: "dmg",          implemented: true,  dryRun: false, mutating: true),
        .init(name: "notarize",     implemented: true,  dryRun: false, mutating: true),
        .init(name: "update",       implemented: true,  dryRun: false, mutating: true),
        .init(name: "ci",           implemented: true,  dryRun: false, mutating: true),
        .init(name: "capabilities", implemented: true,  dryRun: false, mutating: false),
        .init(name: "status",       implemented: true,  dryRun: false, mutating: false),
        .init(name: "recover",      implemented: true,  dryRun: true,  mutating: true),
    ]

    public func run() throws {
        let payload = Payload(
            cliVersion: ReliosCommand.configuration.version,
            schemaVersion: JSONSchema.version,
            commands: Self.registry
        )

        if global.isJSON {
            Report.success(command: "capabilities", data: payload)
        } else {
            print("Relios \(payload.cliVersion) — output schema v\(payload.schemaVersion)")
            print("")
            print("Commands:")
            for c in payload.commands {
                var flags: [String] = []
                if c.dryRun { flags.append("--dry-run") }
                flags.append(c.mutating ? "mutating" : "read-only")
                print("  \(c.name.padding(toLength: 14, withPad: " ", startingAt: 0)) \(flags.joined(separator: ", "))")
            }
        }
    }
}
