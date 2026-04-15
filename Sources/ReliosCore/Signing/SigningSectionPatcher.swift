/// Updates the `[signing]` block inside an existing relios.toml without
/// touching the rest of the file.
///
/// Strategy: locate the `[signing]` header, find the next section header
/// (`[...]`) or EOF, and replace everything in between with a canonical
/// rendering of the supplied values. Whitespace before/after the block
/// is preserved. If no `[signing]` block exists, one is appended at EOF.
///
/// This is deliberately string-level rather than a TOML round-trip because
/// the only TOML library in the build graph is a decoder; a round-trip
/// would reorder keys and drop comments users may have added.
public struct SigningSectionPatcher: Sendable {
    public init() {}

    public struct Values: Sendable {
        public let mode: SigningSection.Mode
        public let identity: String?
        public let teamID: String?
        public let hardenedRuntime: Bool
        public let entitlementsPath: String?

        public init(
            mode: SigningSection.Mode,
            identity: String? = nil,
            teamID: String? = nil,
            hardenedRuntime: Bool = true,
            entitlementsPath: String? = nil
        ) {
            self.mode = mode
            self.identity = identity
            self.teamID = teamID
            self.hardenedRuntime = hardenedRuntime
            self.entitlementsPath = entitlementsPath
        }
    }

    public func patch(_ toml: String, with values: Values) -> String {
        let rendered = render(values)
        let lines = toml.split(separator: "\n", omittingEmptySubsequences: false)

        guard let start = lines.firstIndex(where: { trimmed($0) == "[signing]" }) else {
            // Append a new [signing] block. Ensure exactly one blank line
            // separates it from the previous content.
            let trimmedInput = toml.hasSuffix("\n") ? String(toml.dropLast()) : toml
            return trimmedInput + "\n\n" + rendered + "\n"
        }

        // Find the end: next `[section]` header, or EOF.
        var end = lines.count
        for i in (start + 1)..<lines.count {
            let t = trimmed(lines[i])
            if t.hasPrefix("[") && t.hasSuffix("]") {
                end = i
                break
            }
        }

        var newLines: [Substring] = []
        newLines.append(contentsOf: lines[..<start])
        for line in rendered.split(separator: "\n", omittingEmptySubsequences: false) {
            newLines.append(line)
        }
        // Preserve the blank line (if any) that separated [signing] from the next section.
        if end < lines.count {
            newLines.append("")
            newLines.append(contentsOf: lines[end..<lines.count])
        }
        return newLines.joined(separator: "\n")
    }

    private func render(_ v: Values) -> String {
        return """
        [signing]
        mode = "\(v.mode.rawValue)"
        identity = "\(v.identity ?? "")"
        team_id = "\(v.teamID ?? "")"
        hardened_runtime = \(v.hardenedRuntime ? "true" : "false")
        entitlements_path = "\(v.entitlementsPath ?? "")"
        """
    }

    private func trimmed(_ s: Substring) -> String {
        return s.trimmingPrefix { $0.isWhitespace }.trimmingSuffix { $0.isWhitespace }
    }
}

private extension Substring {
    func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var s = self
        while let last = s.last, predicate(last) { s = s.dropLast() }
        return String(s)
    }
}
