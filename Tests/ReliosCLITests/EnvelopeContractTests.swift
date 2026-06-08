import XCTest
@testable import ReliosCLI
import ReliosCore

/// Locks the JSON wire contract that autonomous agents depend on.
final class EnvelopeContractTests: XCTestCase {

    private struct SamplePayload: Encodable { let value: String }

    private func encodeToDict<E: Encodable>(_ value: E) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // schema_version is pinned to 1 — bumping it is a deliberate breaking change.
    func test_schemaVersionIsOne() throws {
        let data = try encodeToDict(DataEnvelope(command: "t", status: "ok", exitCode: 0, data: SamplePayload(value: "x")))
        XCTAssertEqual(data["schema_version"] as? Int, 1)
        let checks = try encodeToDict(ChecksEnvelope(command: "t", status: "ready", exitCode: 0, checks: []))
        XCTAssertEqual(checks["schema_version"] as? Int, 1)
        let err = try encodeToDict(ErrorEnvelope(command: "t", status: "fail", exitCode: 1, error: sampleError()))
        XCTAssertEqual(err["schema_version"] as? Int, 1)
    }

    // Each envelope carries exactly one of data / checks / error.
    func test_exactlyOneBody() throws {
        let data = try encodeToDict(DataEnvelope(command: "t", status: "ok", exitCode: 0, data: SamplePayload(value: "x")))
        XCTAssertNotNil(data["data"]); XCTAssertNil(data["checks"]); XCTAssertNil(data["error"])

        let checks = try encodeToDict(ChecksEnvelope(command: "t", status: "ready", exitCode: 0, checks: []))
        XCTAssertNotNil(checks["checks"]); XCTAssertNil(checks["data"]); XCTAssertNil(checks["error"])

        let err = try encodeToDict(ErrorEnvelope(command: "t", status: "fail", exitCode: 1, error: sampleError()))
        XCTAssertNotNil(err["error"]); XCTAssertNil(err["data"]); XCTAssertNil(err["checks"])
    }

    // Snake_case keys are part of the contract.
    func test_snakeCaseKeys() throws {
        let env = try encodeToDict(ErrorEnvelope(command: "t", status: "fail", exitCode: 1, error: sampleError()))
        XCTAssertNotNil(env["schema_version"])
        XCTAssertNotNil(env["exit_code"])
        let error = try XCTUnwrap(env["error"] as? [String: Any])
        XCTAssertNotNil(error["requires_human"])
        XCTAssertNotNil(error["id"])
    }

    // exit_code mirrors status: ok→0, fail→1.
    func test_exitCodeMatchesStatus() throws {
        let ok = try encodeToDict(DataEnvelope(command: "t", status: "ok", exitCode: 0, data: SamplePayload(value: "x")))
        XCTAssertEqual(ok["exit_code"] as? Int, 0)
        XCTAssertEqual(ok["status"] as? String, "ok")
        let bad = try encodeToDict(ErrorEnvelope(command: "t", status: "fail", exitCode: 1, error: sampleError()))
        XCTAssertEqual(bad["exit_code"] as? Int, 1)
        XCTAssertEqual(bad["status"] as? String, "fail")
    }

    // A check carries a non-empty id, a severity, requires_human, and a remediation kind.
    func test_checkShape() throws {
        let check = JSONCheck(id: "SPEC_VALID", severity: "ok", title: "spec valid",
                              reason: nil, fix: nil, requiresHuman: false, remediation: .none)
        let env = try encodeToDict(ChecksEnvelope(command: "doctor", status: "ready", exitCode: 0, checks: [check]))
        let checks = try XCTUnwrap(env["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 1)
        let c = checks[0]
        XCTAssertEqual(c["id"] as? String, "SPEC_VALID")
        XCTAssertEqual(c["severity"] as? String, "ok")
        XCTAssertEqual(c["requires_human"] as? Bool, false)
        let rem = try XCTUnwrap(c["remediation"] as? [String: Any])
        XCTAssertEqual(rem["kind"] as? String, "none")
    }

    // Remediation kinds encode with the documented snake_case shape.
    func test_remediationEncoding() throws {
        struct Box: Encodable { let remediation: Remediation }
        let run = try encodeToDict(Box(remediation: .runCommand(command: ["relios", "init"], requiredInputs: ["x"])))
        let r = try XCTUnwrap(run["remediation"] as? [String: Any])
        XCTAssertEqual(r["kind"] as? String, "run_command")
        XCTAssertEqual(r["command"] as? [String], ["relios", "init"])
        XCTAssertEqual(r["required_inputs"] as? [String], ["x"])

        let install = try encodeToDict(Box(remediation: .installTool(tool: "dmgbuild", command: ["pip", "install", "dmgbuild"])))
        let i = try XCTUnwrap(install["remediation"] as? [String: Any])
        XCTAssertEqual(i["kind"] as? String, "install_tool")
        XCTAssertEqual(i["tool"] as? String, "dmgbuild")
    }

    private func sampleError() -> JSONErrorBody {
        JSONErrorBody(id: "BUILD_FAILED", severity: "fail", reason: "boom", fix: "fix it",
                      requiresHuman: true, remediation: .none, step: "build", detail: nil)
    }
}
