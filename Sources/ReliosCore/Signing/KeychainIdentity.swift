import ReliosSupport

/// One row from `security find-identity -v -p codesigning`.
public struct KeychainIdentity: Equatable, Sendable {
    /// 40-char SHA1 of the certificate.
    public let hash: String
    /// The quoted identity string, e.g.
    /// "Developer ID Application: Chan (ABCDE12345)".
    public let name: String

    public init(hash: String, name: String) {
        self.hash = hash
        self.name = name
    }

    /// 10-char Team ID extracted from the trailing parenthesis, or `nil`
    /// if the name doesn't follow Apple's standard format (e.g. Mac
    /// Development certs with no team suffix).
    public var teamID: String? {
        return KeychainIdentity.parseTeamID(from: name)
    }

    public static func parseTeamID(from name: String) -> String? {
        // Match a trailing "(XXXXXXXXXX)" with exactly 10 alphanumeric chars.
        guard let open = name.lastIndex(of: "("),
              let close = name.lastIndex(of: ")"),
              open < close else { return nil }
        let inside = name[name.index(after: open)..<close]
        guard inside.count == 10,
              inside.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return String(inside)
    }
}

/// Lists code-signing identities from the macOS keychain.
public struct KeychainIdentityLister: Sendable {
    private let process: any ProcessRunner

    public init(process: any ProcessRunner) {
        self.process = process
    }

    /// Runs `security find-identity -v -p codesigning` and parses the output.
    /// Returns an empty array if no identities are present (not an error).
    public func list() throws -> [KeychainIdentity] {
        let result: ProcessResult
        do {
            result = try process.runShell(
                "security find-identity -v -p codesigning",
                cwd: nil
            )
        } catch {
            throw SigningError.processFailed(
                command: "security find-identity -v -p codesigning",
                underlying: String(describing: error)
            )
        }
        guard result.exitCode == 0 else {
            throw SigningError.nonZeroExit(
                exitCode: result.exitCode,
                stderrTail: String(result.stderr.suffix(500))
            )
        }
        return KeychainIdentityLister.parse(result.stdout)
    }

    /// Parses `security find-identity` output. Each identity line looks like:
    ///   `  1) ABCDEF...0123 "Developer ID Application: Name (TEAM123456)"`
    /// Lines that don't match this shape (headers, trailer, invalid entries)
    /// are skipped silently.
    public static func parse(_ output: String) -> [KeychainIdentity] {
        var identities: [KeychainIdentity] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingPrefix { $0.isWhitespace }
            // Expect: "<index>) <hash> \"<name>\""
            guard let firstQuote = line.firstIndex(of: "\""),
                  let lastQuote = line.lastIndex(of: "\""),
                  firstQuote < lastQuote else { continue }

            let beforeQuote = line[..<firstQuote]
            // Hash: the whitespace-separated token right before the opening quote.
            let tokens = beforeQuote.split(separator: " ", omittingEmptySubsequences: true)
            guard let hashToken = tokens.last else { continue }
            let hash = String(hashToken)
            guard hash.count == 40,
                  hash.allSatisfy({ $0.isHexDigit }) else { continue }

            let name = String(line[line.index(after: firstQuote)..<lastQuote])
            identities.append(KeychainIdentity(hash: hash, name: name))
        }
        return identities
    }
}
