import Foundation
import ReliosCore

/// Versioned wire schema for `--format json`. Bumping `current` is a deliberate
/// breaking change and is guarded by a contract test.
enum JSONSchema {
    static let version = 1
}

/// A single doctor check in JSON form.
struct JSONCheck: Encodable {
    let id: String
    let severity: String          // ok | warn | fail
    let title: String
    let reason: String?
    let fix: String?
    let requiresHuman: Bool
    let remediation: Remediation

    enum CodingKeys: String, CodingKey {
        case id, severity, title, reason, fix
        case requiresHuman = "requires_human"
        case remediation
    }
}

/// A failure in JSON form.
struct JSONErrorBody: Encodable {
    let id: String
    let severity: String          // always "fail" (or "warn")
    let reason: String
    let fix: String
    let requiresHuman: Bool
    let remediation: Remediation
    let step: String?             // release pipeline step, when applicable
    let detail: String?           // stderr tail / underlying, when applicable

    enum CodingKeys: String, CodingKey {
        case id, severity, reason, fix
        case requiresHuman = "requires_human"
        case remediation, step, detail
    }
}

/// Envelope carrying a success `data` payload.
struct DataEnvelope<D: Encodable>: Encodable {
    let schemaVersion = JSONSchema.version
    let command: String
    let status: String
    let exitCode: Int
    let data: D

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command, status
        case exitCode = "exit_code"
        case data
    }
}

/// Envelope carrying doctor `checks`.
struct ChecksEnvelope: Encodable {
    let schemaVersion = JSONSchema.version
    let command: String
    let status: String
    let exitCode: Int
    let checks: [JSONCheck]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command, status
        case exitCode = "exit_code"
        case checks
    }
}

/// Envelope carrying an `error`.
struct ErrorEnvelope: Encodable {
    let schemaVersion = JSONSchema.version
    let command: String
    let status: String
    let exitCode: Int
    let error: JSONErrorBody

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command, status
        case exitCode = "exit_code"
        case error
    }
}
