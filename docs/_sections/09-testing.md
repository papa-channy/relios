## 9. 테스트 전략

이 섹션은 테스트 코드를 어떻게 작성하느냐에 초점을 둔다. 추상화를 왜 그렇게 잘랐는지(`FileSystem`, `ProcessRunner`, `ArchiveWriter`)는 Section 6에서 다루고, 여기서는 그 추상화를 테스트에서 어떻게 활용하는지만 본다.

### 9.1 테스트 인프라 전반

테스트는 전부 XCTest 기반이며, 현재 **213개 테스트, 0 실패**다.

```
$ swift test
...
Test Suite 'reliosPackageTests.xctest' passed at 2026-05-25 19:22:20.
     Executed 213 tests, with 0 failures (0 unexpected) in 0.066 (0.078) seconds
```

디렉터리 구조는 도메인 슬라이스(Section 6.3 기준)와 1:1로 정렬된다.

```
Tests/
  ReliosCoreTests/
    Build/        Bundle/       CI/          DMG/          Doctor/
    Init/         Inspect/      Install/     Notarize/     Release/
    Rollback/     Signing/      Spec/        Validation/   Version/
    Fixtures/     Helpers/
  bats/
    update-tap-formula.bats
    fixtures/
```

각 도메인 폴더에는 그 슬라이스가 export한 타입에 대한 단위 테스트만 들어간다(예: `Install/AppInstallerTests.swift`는 `AppInstaller`만 다룬다). 슬라이스 간 통합은 `Release/ReleasePipelineTests.swift`가 담당한다.

실행 방법은 단순하다.

```bash
# 전체
swift test

# 단일 스위트
swift test --filter SpecDecodingTests
swift test --filter ReliosCoreTests.NotarizerTests

# bats 통합 테스트
bats Tests/bats/update-tap-formula.bats
```

### 9.2 테스트 헬퍼

`Tests/ReliosCoreTests/Helpers/`에는 production 코드가 아닌, 테스트 전용 fake 4종이 있다. 모두 `@unchecked Sendable`이며 단일 스레드 가정으로 동작한다.

#### `InMemoryFileSystem`

`FileSystem` 프로토콜의 메모리 구현이다. 디스크에 절대 닿지 않는다.

```swift
final class InMemoryFileSystem: FileSystem, @unchecked Sendable {
    private(set) var files: [String: String]
    private(set) var directories: Set<String>

    /// Paths passed to `writeUTF8` since init. Stays empty if no caller wrote.
    /// Used by `ReleasePipelineTests` to lock the dry-run "no writes" invariant.
    private(set) var writeLog: [String] = []
```

세 가지가 중요하다.

1. **자동 부모 디렉터리 등록.** `init`에서 시드된 모든 파일과 디렉터리의 상위 경로를 `directories`에 자동으로 추가한다. `/proj/relios.toml`만 시드해도 `/proj`, `/`가 디렉터리로 인식된다.
2. **`writeLog` 추적.** `writeUTF8`, `copyFile`, `moveItem`, `removeItem`이 호출될 때마다 경로를 누적한다. 삭제는 `"REMOVE:" + path` 형태로 기록된다. dry-run "no writes" 불변식을 잠그는 데 사용된다(`ReleasePipelineTests`).
3. **디렉터리 복사/이동의 prefix-relocation.** `copyFile`이 디렉터리에 대해 호출되면 `srcPrefix → dstPrefix`로 모든 자식을 옮긴다. 실제 `cp -R` 동작에 근사한다.

전형적인 사용 패턴:

```swift
let fs = InMemoryFileSystem(files: [
    "/proj/relios.toml": SampleTOMLs.fullSample,
    "/proj/Package.swift": "",
])
let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
```

#### `MockProcessRunner`

`ProcessRunner` 프로토콜의 fake. 모든 셸 호출을 `calls`에 기록하고, 사전 정의된 결과를 돌려준다.

```swift
final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let command: String
        let cwd: String?
    }
    private(set) var calls: [Call] = []

    /// Command-pattern overrides: if a command contains the key string,
    /// this result is returned instead of the canned/default. Checked first.
    var commandOverrides: [String: ProcessResult] = [:]

    /// Side effects keyed by command substring. When a call's command
    /// contains the key, the closure runs before the result is returned.
    var sideEffects: [String: () -> Void] = [:]
```

세 가지 모드를 조합해 쓴다.

- **단일 default 결과**: `MockProcessRunner(result: .success)` — 모든 호출에 같은 결과.
- **큐 모드**: `MockProcessRunner(queue: [r1, r2, r3], default: .success)` — n번째 호출이 `results[n]`을 받는다. 큐가 비면 default로 폴백.
- **substring override**: `runner.commandOverrides["xcrun notarytool --version"] = ...` — 명령에 키 문자열이 포함되면 큐보다 먼저 매칭된다. presence 체크 시뮬레이션에 유용.
- **`sideEffects`**: 명령이 호출되는 *시점에* fs를 조작하는 클로저. 외부 명령(`ditto -x -k`)이 파일을 만들어내는 부수효과를 흉내내는 유일한 방법이다(9.7 참조).

#### `MockArchiveWriter`

```swift
final class MockArchiveWriter: ArchiveWriter, @unchecked Sendable {
    struct Call: Equatable { let source: String; let destination: String }
    private(set) var calls: [Call] = []
    var shouldFail = false

    /// Optional: if set, writes a placeholder at `destination` so that
    /// backup rotation tests can see the zip in `listDirectory`.
    var fs: InMemoryFileSystem?
```

호출 인자만 기록하는 단순 fake. `shouldFail = true`로 두면 `ArchiveError.dittoFailed`를 던진다. `fs`를 주입하면 결과 파일을 placeholder로 써 줘서 backup rotation 같은 후속 단계가 zip 존재를 볼 수 있게 한다.

#### `TestSpecBuilder`

`ReleaseSpec`는 의도적으로 memberwise init이 없다. 직접 만들 수 없으니, 테스트는 항상 TOML을 거쳐 `SpecLoader`로 빌드한다.

```swift
enum TestSpecBuilder {
    static func spec(
        signingMode: SigningSection.Mode,
        identity: String? = nil,
        ...
    ) -> ReleaseSpec {
        let toml = """
        [app]
        name = "X"
        ...
        [signing]
        mode = "\(signingMode.rawValue)"
        """
        let fs = InMemoryFileSystem(files: ["/proj/relios.toml": toml])
        return try! SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }
}
```

서명 모드만 바꿔서 빠르게 spec을 얻고 싶을 때 쓴다.

### 9.3 Fixture 패턴

`Tests/ReliosCoreTests/Fixtures/SampleTOMLs.swift`에는 TOML 문자열이 Swift 상수로 박혀 있다. **리소스 파일을 쓰지 않는다.** 의도적이다.

```swift
/// TOML fixtures used by SpecDecodingTests.
/// Kept as Swift constants (not loaded from disk) so the test target needs
/// no SwiftPM `resources:` declaration and tests stay self-contained.
enum SampleTOMLs {

    /// Mirrors the canonical example from the v1 spec doc, byte-for-byte.
    /// If this string changes, the test_gate2 assertions must move with it.
    static let fullSample = """
    [app]
    name = "PortfolioManager"
    ...
    """

    static let minimalWithEmptyOptionals = """ ... """
    static let xcodebuildPassthrough = """ ... """
}
```

장점은 세 가지:

- `Package.swift`에 `resources:` 선언이 필요 없다 — 테스트 타겟이 self-contained.
- diff에 fixture 변경이 그대로 드러난다.
- spec 문서의 canonical 예시와 byte-for-byte 일치를 강제한다(주석 참조).

테스트 내부에서 TOML을 **조합**해야 할 때(예: `CIInitRunnerTests`에서 `[dmg]` 블록을 끝에 덧붙일 때)는 fixture를 base로 두고 문자열 concat을 쓴다.

```swift
let toml = assemblyTOML() + """


[dmg]
enabled = true
output_dir = "dist"
"""
```

### 9.4 테스트 카테고리별 작성 패턴

테스트는 크게 다섯 카테고리로 갈린다. 각 카테고리는 공통 셋업 형태를 가진다.

#### Spec decoding 테스트

TOML 문자열 → `SpecLoader` → 필드 단위 어서션. `Tests/ReliosCoreTests/Spec/SpecDecodingTests.swift`가 정석이다. 다섯 개의 "gate"가 acceptance 기준을 잠근다.

```swift
final class SpecDecodingTests: XCTestCase {

    // Gate 2: 모든 section 값 정확히 매핑
    func test_gate2_signing_section_isMappedExactly() throws {
        let spec = try loadFullSample()
        XCTAssertEqual(spec.signing.mode, .adhoc)
    }

    // Gate 3: 빈 문자열 → nil 정규화
    func test_gate3_emptyResourceBundlePath_normalizesToNil() throws {
        let spec = try loadMinimalWithEmptyOptionals()
        XCTAssertNil(spec.build.resourceBundlePath,
                     "empty resource_bundle_path must normalize to nil")
    }

    // Gate 4: 잘못된 TOML → SpecLoadError
    func test_gate4_malformedToml_throwsSpecLoadErrorMalformed() {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": "not [valid = toml { ="
        ])
        XCTAssertThrowsError(try SpecLoader(fs: fs).load(from: "/proj/relios.toml")) { error in
            guard let specError = error as? SpecLoadError else { return XCTFail(...) }
            if case .malformed = specError { /* ok */ } else { XCTFail(...) }
        }
    }

    private func loadFullSample() throws -> ReleaseSpec {
        let fs = InMemoryFileSystem(files: [
            "/proj/relios.toml": SampleTOMLs.fullSample
        ])
        return try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
    }
}
```

#### Validation rule 테스트

`ValidationContext`를 만들고, `rule.evaluate(ctx)` 결과를 `.ok` / `.warn` / `.fail`로 패턴 매칭한다. `XcodeProjectGuardRuleTests`가 좋은 예시다.

```swift
final class XcodeProjectGuardRuleTests: XCTestCase {
    private let rule = XcodeProjectGuardRule()

    func test_failsWhenXcodeprojExistsWithAssemblyMode() throws {
        let context = try makeContext(
            toml: SampleTOMLs.fullSample,
            fs: InMemoryFileSystem(
                files: ["/proj/relios.toml": SampleTOMLs.fullSample],
                directories: ["/proj/MyApp.xcodeproj"]
            )
        )

        let result = rule.evaluate(context)

        guard case .fail(_, let reason, let fix) = result else {
            XCTFail("Expected .fail, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("MyApp.xcodeproj"))
        XCTAssertTrue(fix.contains("passthrough"))
    }

    private func makeContext(toml: String, fs: InMemoryFileSystem) throws -> ValidationContext {
        let spec = try SpecLoader(fs: fs).load(from: "/proj/relios.toml")
        return ValidationContext(spec: spec, projectRoot: "/proj", fs: fs)
    }
}
```

각 룰은 `.ok` / `.warn` / `.fail` 세 분기 전부에 대해 최소 한 개씩 테스트를 둔다. fail 케이스에서는 `reason`과 `fix` 문자열이 사용자에게 의미 있는 키워드를 포함하는지(`contains`)도 같이 확인한다.

#### Runner orchestration 테스트

`MockProcessRunner`로 호출 시퀀스와 인자를 검증한다. `NotarizerTests`가 대표 예시다 — DMG 경로와 ZIP 경로에서 호출되는 명령이 다르다는 contract를 잠근다.

```swift
func test_dmgPathSubmitsThenStaplesTheDMG() throws {
    let fs = InMemoryFileSystem(files: ["/out/app.dmg": "x"])
    let runner = MockProcessRunner(result: ProcessResult(
        exitCode: 0,
        stdout: "status: Accepted",
        stderr: ""
    ))
    let n = Notarizer(fs: fs, process: runner)

    let output = try n.notarize(
        artifactPath: "/out/app.dmg",
        credentials: creds,
        timeoutSeconds: 120
    )

    XCTAssertEqual(output.stapledArtifactPath, "/out/app.dmg")
    let submitCall = runner.calls.first { $0.command.contains("notarytool submit") }
    XCTAssertNotNil(submitCall)
    XCTAssertTrue(submitCall!.command.contains("/out/app.dmg"))
    XCTAssertTrue(submitCall!.command.contains("--wait --timeout 120s"))

    let stapleCall = runner.calls.first { $0.command.contains("stapler staple") }
    XCTAssertNotNil(stapleCall)
    XCTAssertTrue(stapleCall!.command.contains("/out/app.dmg"))

    // No ditto calls (no unzip/rezip for DMG).
    XCTAssertFalse(runner.calls.contains { $0.command.contains("ditto") })
}
```

요점: 명령은 substring으로 매칭하고, **불러야 할 것**과 **부르면 안 되는 것**을 모두 어서트한다. 후자가 regression을 잡는다(예: DMG에는 `ditto`가 절대 호출되면 안 된다).

#### Workflow renderer 테스트

`CIInitRunnerTests`는 spec → render → YAML 문자열 contains 어서션 패턴을 보여준다. 213개 중 가장 많은 비중을 차지하는 카테고리다.

```swift
func test_assembly_specInvokesReliosReleaseInCI() throws {
    let fs = InMemoryFileSystem(files: ["/proj/relios.toml": assemblyTOML()])
    let runner = CIInitRunner(fs: fs)

    let result = try runner.run(projectRoot: "/proj", force: false)

    XCTAssertEqual(result.mode, .assembly)
    XCTAssertEqual(result.projectType, .swiftpm)

    let yaml = try fs.readUTF8(at: "/proj/.github/workflows/release.yml")
    XCTAssertTrue(yaml.contains("brew install papa-channy/relios/relios"))
    XCTAssertTrue(yaml.contains("relios release --skip-backup --no-open"))
    XCTAssertTrue(yaml.contains("dist/PortfolioManager.app"))
    XCTAssertTrue(yaml.contains("PortfolioManager-${TAG}.zip"))
}
```

regression 어서션도 같이 쓴다 — 한 번 깨졌던 동작을 negative contains로 잠근다.

```swift
// Regression: keychain block must not run into the next step's line.
// Earlier bug produced `rm -f "$CERT_PATH"      - name: Install Relios`.
XCTAssertFalse(yaml.contains("$CERT_PATH\"      "))
XCTAssertFalse(yaml.contains("$CERT_PATH\"  -"))
```

주석에 *왜* 이 negative 어서션이 있는지 항상 남긴다. 안 그러면 다음 사람이 무심코 지운다.

#### CLI 출력 테스트

현재 e2e CLI 출력 검증은 일부만 bats로 커버되어 있다(9.5). 더 추가 가능하다 — `relios doctor` 같은 명령의 stdout 정렬, exit code 매트릭스가 좋은 후보.

### 9.5 bats 통합 테스트

`Tests/bats/`에는 셸 스크립트 레벨의 통합 테스트가 있다. 현재는 `update-tap-formula.bats` 하나.

```bash
@test "transform: replaces url and sha256 on canonical formula" {
  run bash -c "source '$SCRIPT' && cat '$FIXTURES/formula.v0.1.0-alpha.rb' \
    | transform_formula v0.2.0 aaaa...aaaa papa-channy/relios"
  [ "$status" -eq 0 ]
  [[ "$output" == *'url "https://github.com/papa-channy/relios/archive/refs/tags/v0.2.0.tar.gz"'* ]]
  [[ "$output" == *'sha256 "aaaa...aaaa"'* ]]
  # Old values must be gone.
  [[ "$output" != *'v0.1.0-alpha.tar.gz'* ]]
}

@test "transform: idempotent on same inputs" {
  ...
}
```

**Prerequisites.**

```bash
brew install bats-core
bats Tests/bats/update-tap-formula.bats
```

스크립트를 `source`해서 내부 함수(`transform_formula`)만 노출시키고, `run` 헬퍼로 stdout/exit를 캡처하는 패턴이다. Fixture(`formula.v0.1.0-alpha.rb`, `formula.no-url.rb`)는 디스크에 둔다 — Ruby 포맷 파일이라 Swift 상수로 두는 게 자연스럽지 않기 때문이다.

### 9.6 새 기능 추가 시 테스트 체크리스트

기능 슬라이스를 추가할 때마다 다음을 확인한다.

- **Spec 변경(필드 추가/변경)**
  - `SampleTOMLs`에 fixture 한 줄 추가 또는 새 상수 추가.
  - `SpecDecodingTests`에 라운드트립 어서션 추가(`XCTAssertEqual(spec.<section>.<field>, ...)`).
  - 옵셔널 필드라면 "빈 문자열 → nil" 정규화 어서션도 추가(Gate 3 패턴).
  - `SpecValidityRuleTests`에 새 필드 검증 룰 추가.

- **새 Doctor rule**
  - 룰 자체 단위 테스트 파일 생성(`Validation/<Rule>Tests.swift` 또는 `Notarize/<Rule>Tests.swift`).
  - **세 분기 전부**에 대해 최소 한 케이스씩: `.ok`, `.warn`, `.fail`.
  - fail 케이스에서 `reason`/`fix` 문자열의 핵심 키워드 contains 어서션.

- **새 ProcessRunner 호출**
  - `MockProcessRunner.calls`에서 substring으로 명령을 찾는 어서션.
  - 명령 인자 substring 어서션(`contains("--wait --timeout")`).
  - **negative 어서션**도 같이 — 이 경로에서 절대 부르면 안 되는 명령은 `XCTAssertFalse(runner.calls.contains { ... })`.
  - 외부 명령이 파일을 만든다면 `sideEffects` 등록(9.7).

- **새 워크플로우 블록(`ci init`)**
  - `CIInitRunnerTests`에 contains 어서션 추가.
  - 해당 블록이 disabled일 때 *생성되지 않아야* 한다는 negative 어서션도 같이.
  - 줄바꿈/들여쓰기 깨짐을 잡기 위한 regression 어서션 — `XCTAssertFalse(yaml.contains("$CERT_PATH\"      "))` 같은 식.

- **YAML smoke 체크(권장)**
  - `ci init` 결과 YAML이 valid한지는 단위 테스트로 잡지 않는다. 로컬에서 한 번 돌리는 게 좋다:
    ```bash
    python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('ok')"
    ```
  - CI에서 actionlint를 돌리는 것도 검토 대상.

### 9.7 테스트 작성 시 회피해야 할 함정

#### `InMemoryFileSystem`은 외부 명령을 모른다

`MockProcessRunner`가 셸 명령을 받아도 **실제로 파일을 옮기지 않는다.** `ditto -x -k`, `cp -R` 같은 부수효과를 의존하는 코드를 테스트하려면 `sideEffects`로 직접 시뮬레이션해야 한다.

```swift
// Simulate ditto -x -k extracting an .app into the scratch dir.
runner.sideEffects["ditto -x -k"] = {
    try? fs.createDirectory(at: "/out/_relios-staple/App.app")
}
```

이걸 빠뜨리면 후속 단계(`stapler staple /out/_relios-staple/App.app`)가 "파일 없음"으로 실패하는데, 원인을 찾기까지 시간이 오래 걸린다. 외부 명령이 출력 파일/디렉터리를 만드는 패턴이면 *항상* `sideEffects`를 짝지어 등록한다.

#### 환경 변수 의존 룰은 env dict로 주입

`NotarizeReadinessRule`처럼 환경 변수를 읽는 룰은 `init(env: [String: String])`을 통해 dict를 주입받는 형태로 설계되어 있다. 테스트는 실제 환경에 의존하지 않는다.

```swift
let (ctx, env) = try makeContext(notarizeTOML: nil, env: [:], notarytoolOK: true)
let result = NotarizeReadinessRule(env: env).evaluate(ctx)
```

새로 추가하는 룰도 같은 패턴을 따른다 — `ProcessInfo.processInfo.environment`를 직접 읽지 말 것. 한 번 박히면 테스트가 CI 환경/로컬 환경에 따라 깜빡거린다.

#### dry-run "no writes" 불변식은 `writeLog`로 잠근다

dry-run 경로가 실제로 디스크를 건드리지 않는다는 사실은 `InMemoryFileSystem.writeLog`가 비어 있는지로 확인한다.

```swift
XCTAssertTrue(fs.writeLog.isEmpty, "dry-run must not write anything")
```

writeLog에는 write/copy/move/remove 모두 누적되므로, "조회만 했음"이 자동으로 잠긴다.

#### SourceKit 진단은 캐시가 stale할 수 있다

에디터에 빨간 줄이 떠도 실제 빌드가 통과하면 문제 없다. 판단은 **`swift build` / `swift test` 결과로**. 의심스러우면 다음을 돌린다.

```bash
swift package clean
rm -rf .build
swift test
```

테스트가 통과한다는 사실이 최종 ground truth다.

#### `swift test --filter`는 substring 매칭이다

```bash
swift test --filter NotarizerTests             # 클래스 이름
swift test --filter test_dmgPathSubmits         # 메서드 이름 일부도 가능
swift test --filter ReliosCoreTests.Notarizer  # 모듈.클래스 prefix
```

이름이 짧으면 의도치 않은 테스트가 같이 잡힐 수 있으므로, 단일 케이스를 돌릴 때는 모듈 prefix까지 명시하는 게 안전하다.
