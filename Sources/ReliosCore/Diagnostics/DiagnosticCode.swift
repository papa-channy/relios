import Foundation

/// A stable, machine-readable identifier for an error or a doctor check.
///
/// The whole point of structured output is that an autonomous agent branches on
/// these IDs instead of parsing human English (which is free to change). IDs are
/// `SCREAMING_SNAKE_CASE`, `<DOMAIN>_<CONDITION>` (e.g. `SIGNING_IDENTITY_NOT_FOUND`,
/// `BUILD_TOOL_NOT_FOUND`). Codes are assigned at the throw/verdict site (each
/// error enum's `code` accessor, each rule's `RuleResult`); `DiagnosticCatalog`
/// maps a code to its agent-actionability (`requiresHuman` + structured
/// `remediation`). Both the human and JSON render paths read the same catalog.
public struct DiagnosticCode: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    // Encode/decode as a bare string, not an object.
    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Verdict severity shared by errors (always warn/fail) and checks (also ok).
public enum Severity: String, Codable, Sendable, Equatable {
    case ok, warn, fail
}

/// A structured, machine-actionable next step for resolving a diagnostic.
/// Encodes as `{ "kind": "...", ... }` so an agent can dispatch on `kind`.
public enum Remediation: Sendable, Equatable, Encodable {
    case none
    /// A command the agent can run. `requiredInputs` lists placeholders it must
    /// fill (e.g. a `.p12` path) — the signal that it's *almost* runnable.
    case runCommand(command: [String], requiredInputs: [String])
    case editConfig(file: String, keys: [String])
    case setEnv(keys: [String])
    case installTool(tool: String, command: [String])

    private enum CodingKeys: String, CodingKey {
        case kind, command, requiredInputs = "required_inputs", file, keys, tool
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .kind)
        case .runCommand(let command, let requiredInputs):
            try c.encode("run_command", forKey: .kind)
            try c.encode(command, forKey: .command)
            try c.encode(requiredInputs, forKey: .requiredInputs)
        case .editConfig(let file, let keys):
            try c.encode("edit_config", forKey: .kind)
            try c.encode(file, forKey: .file)
            try c.encode(keys, forKey: .keys)
        case .setEnv(let keys):
            try c.encode("set_env", forKey: .kind)
            try c.encode(keys, forKey: .keys)
        case .installTool(let tool, let command):
            try c.encode("install_tool", forKey: .kind)
            try c.encode(tool, forKey: .tool)
            try c.encode(command, forKey: .command)
        }
    }
}

/// Agent-actionability for a given code: can an agent self-remediate, and how.
public struct DiagnosticDescriptor: Sendable, Equatable {
    public let requiresHuman: Bool
    public let remediation: Remediation

    public init(requiresHuman: Bool, remediation: Remediation = .none) {
        self.requiresHuman = requiresHuman
        self.remediation = remediation
    }
}

/// Single source of truth mapping a `DiagnosticCode` to its actionability.
///
/// Codes not listed default to `requiresHuman: false, remediation: .none` —
/// most config/spec problems are agent-fixable by editing `relios.toml`. The
/// entries below are the cases where that default is wrong (a human/secret is
/// needed) or where a concrete machine action exists.
public enum DiagnosticCatalog {
    public static func descriptor(for code: DiagnosticCode) -> DiagnosticDescriptor {
        entries[code] ?? DiagnosticDescriptor(requiresHuman: false, remediation: .none)
    }

    /// True if the catalog has an explicit entry for this code (used by tests
    /// to confirm the important cases are classified, not silently defaulted).
    public static func isKnown(_ code: DiagnosticCode) -> Bool {
        entries[code] != nil
    }

    private static let entries: [DiagnosticCode: DiagnosticDescriptor] = [
        // --- needs a human (secret / artifact / GUI install) ---
        DiagnosticCode("SIGNING_IDENTITY_NOT_FOUND"): .init(
            requiresHuman: true,
            remediation: .runCommand(command: ["relios", "signing", "import", "<path-to.p12>"],
                                     requiredInputs: ["path-to.p12"])),
        DiagnosticCode("SIGNING_CERT_PASSWORD_MISSING"): .init(
            requiresHuman: true, remediation: .setEnv(keys: ["RELIOS_CERT_PASSWORD"])),
        DiagnosticCode("BUILD_TOOL_NOT_FOUND"): .init(
            requiresHuman: true,
            remediation: .installTool(tool: "swift/xcodebuild",
                                      command: ["xcode-select", "--install"])),
        DiagnosticCode("CODESIGN_NOT_FOUND"): .init(
            requiresHuman: true,
            remediation: .installTool(tool: "codesign", command: ["xcode-select", "--install"])),
        DiagnosticCode("NOTARIZE_CREDENTIALS_MISSING"): .init(
            requiresHuman: true,
            remediation: .setEnv(keys: ["APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD", "APPLE_TEAM_ID"])),
        DiagnosticCode("NOTARYTOOL_NOT_FOUND"): .init(
            requiresHuman: true,
            remediation: .installTool(tool: "Xcode", command: ["# install full Xcode 13+"])),
        DiagnosticCode("NOTARIZE_TEAM_ID_MISMATCH"): .init(
            requiresHuman: true, remediation: .editConfig(file: "relios.toml", keys: ["signing.team_id"])),
        DiagnosticCode("NOTARIZE_REJECTED"): .init(requiresHuman: true),
        DiagnosticCode("NOTARIZE_INVALID"): .init(requiresHuman: true),
        DiagnosticCode("BUILD_FAILED"): .init(requiresHuman: true),

        // --- agent-fixable, concrete action ---
        DiagnosticCode("SPEC_NOT_FOUND"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "init"], requiredInputs: [])),
        DiagnosticCode("SIGNING_IDENTITY_UNSET"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "signing", "setup"], requiredInputs: [])),
        DiagnosticCode("SIGNING_TEAM_ID_UNSET"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "signing", "setup"], requiredInputs: [])),
        DiagnosticCode("NOTARIZE_REQUIRES_DEVID"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["signing.mode"])),
        DiagnosticCode("DMG_TOOL_NOT_FOUND"): .init(
            requiresHuman: false,
            remediation: .installTool(tool: "dmgbuild", command: ["pip", "install", "dmgbuild"])),
        DiagnosticCode("INSTALL_APP_NOT_FOUND"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "release"], requiredInputs: [])),
        DiagnosticCode("ROLLBACK_NO_BACKUPS"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "release"], requiredInputs: [])),
        DiagnosticCode("SPEC_BUNDLE_ID_EMPTY"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["app.bundle_id"])),
        DiagnosticCode("SPEC_NAME_EMPTY"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["app.name"])),
        DiagnosticCode("SPEC_BINARY_TARGET_EMPTY"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["project.binary_target"])),
        DiagnosticCode("VERSION_SOURCE_MISSING"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["version.source_file"])),
        DiagnosticCode("INSTALL_PATH_PARENT_MISSING"): .init(
            requiresHuman: false, remediation: .runCommand(command: ["relios", "doctor", "--fix"], requiredInputs: [])),
        DiagnosticCode("UPDATE_DISABLED"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["update.enabled"])),
        DiagnosticCode("PROJECT_TYPE_MISMATCH"): .init(
            requiresHuman: false, remediation: .editConfig(file: "relios.toml", keys: ["bundle.mode", "project.type"])),
    ]
}
