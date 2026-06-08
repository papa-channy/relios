public struct BuildSection: Decodable, Equatable, Sendable {
    /// Legacy shell command string, run via `/bin/sh -c`. Still supported for
    /// back-compat, but `doctor` warns unless `allow_shell = true` because it
    /// executes arbitrary shell. Prefer `executable` + `arguments`.
    public let command: String
    /// Preferred: the build executable, run WITHOUT a shell (no metacharacter
    /// expansion / injection). When set, this takes precedence over `command`.
    public let executable: String?
    /// Arguments for `executable`.
    public let arguments: [String]
    /// Opt in to running the shell `command` without a doctor warning.
    public let allowShell: Bool
    public let binaryPath: String
    public let resourceBundlePath: String?

    private enum CodingKeys: String, CodingKey {
        case command
        case executable
        case arguments
        case allowShell         = "allow_shell"
        case binaryPath         = "binary_path"
        case resourceBundlePath = "resource_bundle_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.command    = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        let exe = try c.decodeIfPresent(String.self, forKey: .executable)
        self.executable = (exe?.isEmpty == false) ? exe : nil
        self.arguments  = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        self.allowShell = try c.decodeIfPresent(Bool.self, forKey: .allowShell) ?? false
        self.binaryPath = try c.decode(String.self, forKey: .binaryPath)
        let raw = try c.decodeIfPresent(String.self, forKey: .resourceBundlePath)
        self.resourceBundlePath = (raw?.isEmpty == false) ? raw : nil
    }

    public init(
        command: String = "",
        executable: String? = nil,
        arguments: [String] = [],
        allowShell: Bool = false,
        binaryPath: String,
        resourceBundlePath: String? = nil
    ) {
        self.command = command
        self.executable = executable
        self.arguments = arguments
        self.allowShell = allowShell
        self.binaryPath = binaryPath
        self.resourceBundlePath = resourceBundlePath
    }

    /// True when the safe argv form (`executable`) is configured.
    public var usesArgv: Bool { executable != nil }

    /// Human-readable command for summaries, CI YAML, and manifests.
    public var displayCommand: String {
        if let executable, !executable.isEmpty {
            return ([executable] + arguments).joined(separator: " ")
        }
        return command
    }
}
