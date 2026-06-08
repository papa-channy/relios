import Foundation
import ReliosCore

/// Emits the JSON envelopes to stdout. The single place that serializes output
/// for `--format json`. Human output stays in each command's existing prints;
/// commands branch on `global.isJSON` and call these helpers for the JSON path.
///
/// Contract: in JSON mode exactly one JSON object is written to stdout (success
/// OR error), and the envelope's `exit_code` mirrors the process exit the
/// command then performs.
enum Report {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Readable + stable: sorted keys, unescaped slashes (URLs stay legible).
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static func emit<E: Encodable>(_ envelope: E) {
        guard let data = try? encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else {
            // Encoding the envelope should never fail; if it does, surface a
            // minimal valid error object so the agent still gets parseable JSON.
            print(#"{"schema_version":\#(JSONSchema.version),"status":"fail","exit_code":1,"error":{"id":"OUTPUT_ENCODING_FAILED","severity":"fail","reason":"could not encode JSON output","fix":"report this bug","requires_human":true,"remediation":{"kind":"none"}}}"#)
            return
        }
        print(json)
    }

    /// Success payload → `data` envelope (exit 0).
    static func success<D: Encodable>(command: String, status: String = "ok", data: D) {
        emit(DataEnvelope(command: command, status: status, exitCode: 0, data: data))
    }

    /// Doctor diagnostics → `checks` envelope. Status/exit derived from failures.
    static func checks(command: String, diagnostics: [Diagnostic]) {
        let hasFail = diagnostics.contains { $0.status == .fail }
        let jsonChecks = diagnostics.map(Self.check(from:))
        emit(ChecksEnvelope(
            command: command,
            status: hasFail ? "not_ready" : "ready",
            exitCode: hasFail ? 1 : 0,
            checks: jsonChecks
        ))
    }

    /// Failure → `error` envelope (exit 1). The caller still throws ExitCode.failure.
    static func failure(
        command: String,
        code: DiagnosticCode,
        reason: String,
        fix: String,
        step: String? = nil,
        detail: String? = nil
    ) {
        let descriptor = DiagnosticCatalog.descriptor(for: code)
        emit(ErrorEnvelope(
            command: command,
            status: "fail",
            exitCode: 1,
            error: JSONErrorBody(
                id: code.rawValue,
                severity: "fail",
                reason: reason,
                fix: fix,
                requiresHuman: descriptor.requiresHuman,
                remediation: descriptor.remediation,
                step: step,
                detail: detail
            )
        ))
    }

    // MARK: - mapping

    private static func check(from d: Diagnostic) -> JSONCheck {
        let descriptor = DiagnosticCatalog.descriptor(for: d.code)
        return JSONCheck(
            id: d.code.rawValue,
            severity: d.severity.rawValue,
            title: d.title,
            reason: d.reason,
            fix: d.fix,
            requiresHuman: descriptor.requiresHuman,
            remediation: descriptor.remediation
        )
    }
}
