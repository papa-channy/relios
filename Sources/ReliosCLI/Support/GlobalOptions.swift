import ArgumentParser
import Foundation

/// Output format shared by every leaf command. `json` is a stable, versioned
/// contract for scripting and autonomous agents; `human` is the default.
public enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case human
    case json
}

/// Flags shared across all leaf commands. swift-argument-parser does NOT
/// propagate a parent command's flags to subcommands, so this group is
/// included via `@OptionGroup` on each leaf that produces output.
public struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Output format: human | json (or set RELIOS_FORMAT).")
    public var format: OutputFormat?

    public init() {}

    /// Resolved precedence: explicit `--format` flag, then `RELIOS_FORMAT`
    /// env var, then `human`. Leaving `format` optional (not defaulted) lets
    /// the env var take effect when the flag is absent.
    public var resolvedFormat: OutputFormat {
        if let format { return format }
        if let env = ProcessInfo.processInfo.environment["RELIOS_FORMAT"]?.lowercased(),
           let parsed = OutputFormat(rawValue: env) {
            return parsed
        }
        return .human
    }

    public var isJSON: Bool { resolvedFormat == .json }
}
