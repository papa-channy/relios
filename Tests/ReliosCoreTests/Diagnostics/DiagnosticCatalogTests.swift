import XCTest
import ReliosCore
import ReliosSupport

/// Locks the id → requires_human → remediation classification an agent relies on.
final class DiagnosticCatalogTests: XCTestCase {

    func test_humanRequiredCodes() {
        XCTAssertTrue(DiagnosticCatalog.descriptor(for: DiagnosticCode("SIGNING_IDENTITY_NOT_FOUND")).requiresHuman)
        XCTAssertTrue(DiagnosticCatalog.descriptor(for: DiagnosticCode("NOTARIZE_CREDENTIALS_MISSING")).requiresHuman)
        XCTAssertTrue(DiagnosticCatalog.descriptor(for: DiagnosticCode("BUILD_TOOL_NOT_FOUND")).requiresHuman)
        XCTAssertTrue(DiagnosticCatalog.descriptor(for: DiagnosticCode("BUILD_FAILED")).requiresHuman)
    }

    func test_agentFixableCodes() {
        XCTAssertFalse(DiagnosticCatalog.descriptor(for: DiagnosticCode("DMG_TOOL_NOT_FOUND")).requiresHuman)
        XCTAssertFalse(DiagnosticCatalog.descriptor(for: DiagnosticCode("SPEC_NOT_FOUND")).requiresHuman)
        XCTAssertFalse(DiagnosticCatalog.descriptor(for: DiagnosticCode("INSTALL_APP_NOT_FOUND")).requiresHuman)
    }

    func test_remediationShapes() {
        if case .runCommand(let cmd, let inputs) = DiagnosticCatalog.descriptor(for: DiagnosticCode("SIGNING_IDENTITY_NOT_FOUND")).remediation {
            XCTAssertEqual(cmd.first, "relios")
            XCTAssertTrue(inputs.contains("path-to.p12"))
        } else {
            XCTFail("expected runCommand remediation")
        }
        if case .installTool = DiagnosticCatalog.descriptor(for: DiagnosticCode("DMG_TOOL_NOT_FOUND")).remediation {
            // ok
        } else {
            XCTFail("expected installTool remediation")
        }
    }

    func test_unknownCodeDefaultsToAgentFixableNone() {
        let d = DiagnosticCatalog.descriptor(for: DiagnosticCode("TOTALLY_UNKNOWN_CODE"))
        XCTAssertFalse(d.requiresHuman)
        XCTAssertEqual(d.remediation, .none)
        XCTAssertFalse(DiagnosticCatalog.isKnown(DiagnosticCode("TOTALLY_UNKNOWN_CODE")))
        XCTAssertTrue(DiagnosticCatalog.isKnown(DiagnosticCode("SIGNING_IDENTITY_NOT_FOUND")))
    }

    /// Every doctor check carries a non-empty, machine-readable code and a valid
    /// severity — the whole point of structured output (no English parsing).
    func test_everyDoctorCheckHasCodeAndSeverity() throws {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample,
            "/proj/DesignMe/App/AppVersion.swift": """
            enum AppVersion {
                static let current = "1.2.3"
                static let build = "17"
            }
            """,
        ], directories: ["/Applications"])
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        let context = ValidationContext(spec: spec, projectRoot: "/proj", fs: fs, process: MockProcessRunner(result: .success))

        let runner = DoctorRunner(rules: [
            XcodeProjectGuardRule(), SpecValidityRule(), VersionSourceRule(),
            BuildReadinessRule(), InstallPathRule(), SigningReadinessRule(),
            DMGReadinessRule(), NotarizeReadinessRule(), UpdateReadinessRule(),
        ])

        let diagnostics = runner.run(context)
        XCTAssertEqual(diagnostics.count, 9)
        for d in diagnostics {
            XCTAssertFalse(d.code.rawValue.isEmpty, "check '\(d.title)' has an empty code")
            XCTAssertTrue([.ok, .warn, .fail].contains(d.severity))
        }
    }
}
