/// Apple credentials for `xcrun notarytool`. Always read from the
/// environment — TOML never carries these.
///
/// `APPLE_APP_SPECIFIC_PASSWORD` is issued at appleid.apple.com →
/// Security → App-Specific Passwords. The regular Apple ID password
/// won't work because notarytool's endpoint requires app-specific.
public struct NotarizerCredentials: Equatable, Sendable {
    public let appleID: String
    public let password: String
    public let teamID: String

    public init(appleID: String, password: String, teamID: String) {
        self.appleID = appleID
        self.password = password
        self.teamID = teamID
    }

    public static let envVarNames = [
        "APPLE_ID",
        "APPLE_APP_SPECIFIC_PASSWORD",
        "APPLE_TEAM_ID",
    ]

    /// Lifts a credential tuple out of `env`. Missing or empty vars are
    /// reported together so the user fixes them all in one shot instead
    /// of re-running three times.
    public static func fromEnvironment(
        _ env: [String: String]
    ) throws -> NotarizerCredentials {
        var missing: [String] = []
        func pick(_ key: String) -> String {
            let v = env[key] ?? ""
            if v.isEmpty { missing.append(key) }
            return v
        }
        let appleID  = pick("APPLE_ID")
        let password = pick("APPLE_APP_SPECIFIC_PASSWORD")
        let teamID   = pick("APPLE_TEAM_ID")

        if !missing.isEmpty {
            throw NotarizeError.missingCredentials(envVars: missing)
        }
        return NotarizerCredentials(
            appleID: appleID,
            password: password,
            teamID: teamID
        )
    }
}
