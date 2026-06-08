## 6. 내부 아키텍처

이 섹션은 Relios의 코드 구조와 설계 원칙을 정리한다. 사용 방법은 7장, Doctor 규칙 개별 설명은 8장, 테스트 헬퍼는 9장에 위치한다.

### 6.1 3계층 모듈 구성

`Package.swift`는 4개의 타깃을 정의한다. 의존성은 단방향이고, 위쪽 타깃이 아래쪽을 import한다.

```
┌────────────────────────────────────────────┐
│ relios (executableTarget)                  │  ← Sources/relios/main.swift
│   ReliosCommand.main()                     │
└────────────────┬───────────────────────────┘
                 │ depends on
                 ▼
┌────────────────────────────────────────────┐
│ ReliosCLI (target)                         │  ← ArgumentParser dispatch
│   ReliosCommand + Commands/*.swift         │
└────────┬──────────────────────┬────────────┘
         │                      │
         ▼                      ▼
┌──────────────────────┐  ┌────────────────────┐
│ ReliosCore           │  │ ReliosSupport      │
│   도메인 로직 전부    │→ │   FileSystem,      │
│   (Build, Bundle,    │  │   ProcessRunner,   │
│   DMG, Notarize, …)  │  │   ArchiveWriter    │
└──────────────────────┘  └────────────────────┘
         │
         ▼
   TOMLDecoder (third-party, Core 내부에만 노출)
```

- **`relios`**: 단 한 줄짜리 executable. `Sources/relios/main.swift`는 `ReliosCommand.main()`만 호출하고 그 외 로직은 일절 두지 않는다. CI에서 실행 진입점을 fork 한 번이라도 쉽게 바꿀 수 있게 하기 위함이다.
- **`ReliosCLI`**: ArgumentParser 기반. `ReliosCommand`가 12개의 subcommand(`InitCommand`, `DoctorCommand`, `ReleaseCommand`, `BuildCommand`, `InstallCommand`, `InspectCommand`, `RollbackCommand`, `OpenCommand`, `CICommand`, `SigningCommand`, `DMGCommand`, `NotarizeCommand`)를 dispatch 한다. 각 Command는 옵션 파싱과 콘솔 출력만 책임지고, 실제 작업은 Core 슬라이스로 위임한다.
- **`ReliosCore`**: 외부 SDK 의존이 없는 순수 Swift 로직. 유일한 외부 의존은 `TOMLDecoder` 단 한 곳(`Spec/SpecLoader.swift`)에서만 사용된다 — TOML 라이브러리를 교체하더라도 한 파일만 손대면 된다. Doctor/Release/CI 등 모든 도메인이 여기 들어있다.
- **`ReliosSupport`**: I/O와 프로세스 호출을 추상화하는 경계 프로토콜 모음. Foundation 외부 의존이 없다. 테스트가 Core 로직을 검증할 때 Support의 인터페이스만 가짜로 갈아끼우면 디스크나 셸을 건드리지 않고도 분기 전부를 커버할 수 있다.

`ReliosCoreTests`는 `ReliosCore`와 `ReliosSupport`에만 의존한다(`ReliosCLI`에는 의존하지 않음). CLI 계층은 출력 포매팅 외에는 거의 비어 있어서, 도메인 단위로 테스트를 작성하는 게 비용 대비 가장 효율적이다.

### 6.2 ReliosCore 도메인 슬라이스 구성

`Sources/ReliosCore/` 아래는 도메인별 폴더로 슬라이스되어 있다. 각 폴더는 자체 `*Error` 타입과 한두 개의 Runner/Writer/Builder 타입을 가진다.

| 슬라이스 | 책임 |
|----------|------|
| `Build/` | `swift build`(또는 사용자 정의 빌드 명령) 실행과 산출 바이너리 위치 추적. `SwiftBuildRunner`, `BuildError` |
| `Bundle/` | 바이너리 + 리소스 + Info.plist를 `.app` 디렉토리 구조로 조립. `AppBundleAssembler`, `InfoPlistWriter`, `BundleError` |
| `CI/` | GitHub Actions YAML 렌더링 (`ci.yml`, `release.yml`)과 CI 환경 readiness 규칙. `CIWorkflowRenderer`, `ReleaseWorkflowRenderer`, `CIInitRunner` |
| `DMG/` | dmgbuild용 settings.py 렌더링과 DMG 생성 호출. `DMGBuilder`, `DMGSettingsRenderer`, `DMGError` |
| `Doctor/` | 검증 규칙 일괄 실행과 진단 리포트 생성. `DoctorRunner`, `Diagnostic` |
| `Init/` | 프로젝트 스캔(`Package.swift`/`.xcodeproj` 감지)과 `relios.toml` 스켈레톤 생성. `ProjectScanner`, `SpecSkeletonWriter` |
| `Inspect/` | 설치된 `.app`의 Info.plist 읽기와 메타데이터 추출. `InspectReader` |
| `Install/` | 백업/종료/복사/실행 4단계 설치 워크플로우. `BackupManager`, `RunningAppTerminator`, `AppInstaller`, `AppLauncher` |
| `Notarize/` | Apple 공증 제출/대기/스테이플. `Notarizer`, `NotarizerCredentials`, `NotarizeTargetResolver` |
| `Release/` | 빌드→번들→서명→설치 전체 파이프라인 조립. `ReleasePipeline`, `ReleaseManifest`, `ReleaseSummary`, `ReleaseStep` |
| `Rollback/` | 가장 최근 백업 zip을 찾아 복원. `RollbackRunner`, `RollbackError` |
| `Signing/` | ad-hoc / Developer ID 서명 분기, 키체인 ID 조회. `AdhocSigner`, `DeveloperIDSigner`, `KeychainIdentity` |
| `Spec/` | `relios.toml` 디코딩과 섹션별 모델 정의. `SpecLoader`, `ReleaseSpec`, `*Section.swift` |
| `Validation/` | `ValidationRule` 프로토콜과 8개 구현 규칙. Doctor와 Release.preflight가 공통 소비 |
| `Version/` | SemVer/빌드 번호 파싱, 소스 파일에서 정규식으로 읽고 쓰기. `VersionSourceReader`, `VersionSourceUpdater`, `SemanticVersion`, `BuildNumber` |

폴더 = 슬라이스 = 한 가지 동사. 한 슬라이스 안에는 보통 `*Runner`/`*Writer`/`*Builder`(동작) + `*Error`(실패) + 옵션으로 모델 타입이 모인다. 슬라이스 사이를 직접 호출하는 건 `ReleasePipeline`처럼 명시적으로 그것을 위해 존재하는 조립 타입뿐이다.

### 6.3 데이터 흐름: TOML → Spec → 검증 → 실행

```
       ┌─────────────────┐
       │   relios.toml   │   (사용자가 편집)
       └────────┬────────┘
                │  fs.readUTF8 + TOMLDecoder
                ▼
       ┌─────────────────┐
       │   SpecLoader    │   ← Spec/SpecLoader.swift
       └────────┬────────┘
                │  throws SpecLoadError on malformed
                ▼
       ┌─────────────────┐
       │  ReleaseSpec    │   ← Decodable 모델 (Spec/ReleaseSpec.swift)
       └────────┬────────┘
                │  + projectRoot, fs, process
                ▼
       ┌──────────────────────┐
       │ ValidationContext    │   ← 모든 규칙이 공유하는 입력 묶음
       └────────┬─────────────┘
                │
        ┌───────┴────────┐
        ▼                ▼
  ┌───────────┐    ┌────────────────────┐
  │ Doctor    │    │ Release.preflight  │
  │ Runner    │    │  (fail-fast 모드)   │
  └─────┬─────┘    └─────────┬──────────┘
        │ 모든 규칙 평가       │ 첫 .fail에서 throw
        ▼                    ▼
  [Diagnostic]         ReleasePipeline (15 step)
                              │
                              ▼
                       ReleaseManifest write
                       (dist/releases/*.json)
```

핵심은 동일한 `ValidationContext`와 동일한 `[any ValidationRule]` 리스트를 두 진입점(`relios doctor`와 `relios release`의 preflight)이 공유한다는 점이다. Doctor는 결과를 모두 모아 `[Diagnostic]`로 보여주는 "탐색" 모드, Release.preflight는 첫 `.fail`에서 즉시 throw 하는 "방어" 모드. 규칙 자체는 두 모드를 모른다.

### 6.4 경계 인터페이스(boundary protocols)

`ReliosSupport`의 프로토콜 3종은 도메인 코드가 디스크/셸/zip에 직접 접근하지 못하게 막는 차단막이다.

**`FileSystem`** — `Sources/ReliosSupport/FileSystem.swift`. 모든 파일 IO가 통과해야 하는 인터페이스. 9개 메서드(`fileExists`, `isDirectory`, `listDirectory`, `readUTF8`, `writeUTF8`, `copyFile`, `removeItem`, `moveItem`, `createDirectory`). 프로덕션은 `RealFileSystem`이 `FileManager.default`를 그대로 감싸고, 테스트는 `InMemoryFileSystem`이 dictionary로 가상 트리를 흉내낸다. 도메인 타입이 `FileManager`를 직접 import 하는 건 사실상 금지 — `SpecLoader`도 `AppBundleAssembler`도 `BackupManager`도 전부 주입받은 `any FileSystem`만 통한다.

**`ProcessRunner`** — `Sources/ReliosSupport/ProcessRunner.swift`. 모든 subprocess가 통과하는 인터페이스. 두 가지 entrypoint만 노출한다:
- `runShell(_:cwd:)` — 버퍼링 모드. 작업이 끝난 뒤 stdout/stderr를 한꺼번에 반환. `swift build`, `codesign` 같이 짧고 결과를 파싱해야 하는 호출에 사용.
- `runShellStreaming(_:cwd:)` — tee 모드. 각 청크를 부모의 stdout/stderr에 실시간으로 흘리면서 동시에 버퍼에도 적재. `notarytool submit`이나 `brew install`처럼 장시간 도는 명령이 CI 로그에서 침묵하지 않도록 하기 위함. 기본 구현이 `runShell`로 폴백하므로 기존 mock은 영향을 받지 않는다.

`runShell`이 non-zero exit에 throw 하지 않는 것도 의도된 설계 — "실패"의 정의는 호출자가 도메인 의미에 맞춰 결정한다(예: `stapler validate`의 exit 65는 재시도, 64는 fatal).

**`ArchiveWriter`** — `Sources/ReliosSupport/ArchiveWriter.swift`. zip 생성. 프로덕션 구현 `DittoArchiveWriter`는 `/usr/bin/ditto -c -k --keepParent`를 호출해 xattr/리소스 포크를 보존한다(나중 codesign이 깨지지 않게). 테스트는 `MockArchiveWriter`로 대체.

**왜 이렇게 분리했나.** 두 가지 목적이 겹친다. (1) 테스트 용이성 — Core의 if/else 분기 전부를 디스크 안 건드리고 검증할 수 있다(9장 참조). (2) 미래 교체 여지 — TOML 백엔드를 다른 파서로 바꾸거나, ditto 대신 다른 archiver를 쓰거나, Process 대신 swift-subprocess를 쓰는 변경이 도메인 코드에 전혀 닿지 않는다. `Package.swift`의 외부 의존은 `swift-argument-parser`와 `TOMLDecoder` 단 두 개뿐이며, 둘 다 한 모듈/한 파일에만 노출되어 있다.

### 6.5 ValidationRule 패턴

검증 시스템은 의도적으로 미니멀하다. `Sources/ReliosCore/Validation/`:

```swift
public protocol ValidationRule: Sendable {
    func evaluate(_ context: ValidationContext) -> RuleResult
}
```

associatedtype을 두지 않은 게 핵심 결정 사항이다. 모든 규칙이 동일한 `ValidationContext`(spec + projectRoot + fs + 선택적 process)를 받고 그중 필요한 필드만 골라 본다. 덕분에 `[any ValidationRule]` 배열에 이질적인 규칙들을 그대로 담을 수 있다.

```swift
public enum RuleResult: Sendable, Equatable {
    case ok(title: String)
    case warn(title: String, reason: String, fix: String)
    case fail(title: String, reason: String, fix: String)
}
```

`title`이 case마다 들어있는 이유: 한 규칙이 여러 실패 모드를 가질 수 있다. 예를 들어 `SpecValidityRule`은 `"app.name is empty"`와 `"bundle_id is empty"`를 같은 규칙 안에서 다른 title로 돌려준다.

**소비 측은 두 곳이다.**

- `DoctorRunner.run(_:)` — 모든 규칙을 끝까지 평가해서 `[Diagnostic]` 생성. `RuleResult` → `Diagnostic` 변환만 한다. 병렬화 없음, auto-fix 디스패치 없음(v1).
- `ReleasePipeline.preflightValidation(...)` — 같은 규칙 리스트(`XcodeProjectGuardRule`, `SpecValidityRule`, `VersionSourceRule`, `BuildReadinessRule`, `SigningReadinessRule`)를 순회하다 첫 `.fail`을 만나면 즉시 `ReleaseError.preflightFailed(ruleTitle:reason:fix:)`로 throw. CLI는 이걸 `[stage: preflight] failed: <title> — <reason>` 한 줄로 출력한다.

규칙 개별 의미(어떤 조건에서 .fail/.warn이 나오는지)는 8장에서 다룬다. 여기서는 메커니즘만.

### 6.6 ReleasePipeline 흐름

`Sources/ReliosCore/Release/ReleasePipeline.swift`. 한 메서드 `run(spec:projectRoot:options:)`가 다음 단계를 순서대로 실행한다. dry-run/passthrough/assembly 모드에 따라 일부 단계가 스킵된다.

| # | 단계 (ReleaseStep) | dry-run | assembly | passthrough |
|---|---|:---:|:---:|:---:|
| 1 | preflightValidation | run | run | run |
| 2 | readCurrentVersion | run | run | run |
| 3 | computeNextVersion | run | run | run |
| 4 | build (`swift build` 등) | run | run | run |
| 5 | verifyBuildArtifact / verifyAppExists | run | run | run |
| 6 | updateVersionSource | skip | run | run |
| 7 | assembleAppBundle | skip | run | **skip** |
| 8 | writeInfoPlist | skip | run | **skip** |
| 9 | sign (adhoc / developerID / keep) | skip | run | run |
| 10 | backupExistingApp | skip | run* | run* |
| 11 | terminateRunningApp | skip | run† | run† |
| 12 | installApp | skip | run | run |
| 13 | launchApp | skip | run‡ | run‡ |
| 14 | writeReleaseManifest | skip | run | run |

\* `options.skipBackup`이면 스킵.  
† `spec.install.quitRunningApp == true`일 때만.  
‡ `spec.install.autoOpen && !options.noOpen`일 때만.

핵심 규칙 두 가지:
- **dry-run의 불변식**: 1–5단계까지만 실행하고 디스크 쓰기는 한 줄도 없다. dry-run을 돌렸다가 어떤 파일이 새로 생겼다면 그건 버그다(테스트가 `FileSystem.snapshot()`로 강제).
- **passthrough vs assembly의 차이**: passthrough 모드(사용자의 `xcodebuild`가 `.app`을 다 만든 경우)는 7,8단계(bundle 조립 + Info.plist 쓰기)를 건너뛴다. 이미 완성된 `.app`을 서명만 다시 한다.

각 단계의 도메인 에러(`BuildError`, `VersionSourceError`, `SigningError`, `BundleError`, `InstallError`)는 파이프라인 내부에서 catch 되어 `ReleaseError`의 대응 case로 재포장된다. 덕분에 CLI는 단 하나의 enum만 switch 하면 된다.

### 6.7 CI 워크플로우 렌더링 전략

`Sources/ReliosCore/CI/ReleaseWorkflowRenderer.swift`. `render(_ spec:)` 한 메서드가 spec을 보고 YAML 문자열을 조립한다.

**렌더링은 블록 단위의 조건부 주입.** 7~8개의 private 메서드(`header`, `keychainSetupBlock`, `buildStepsBlock`, `dmgStepsBlock`, `notarizeStepsBlock`, `publishStep`, `keychainCleanupBlock`)가 각자 자기 책임의 블록만 만들고, top-level `render`가 spec의 플래그 3개를 보고 어떤 블록을 끼울지 결정한다:

```
dmgEnabled   = spec.dmg?.enabled == true
devIDSigning = spec.signing.mode == .developerID
notarize     = spec.notarize?.enabled == true
```

| 블록 | 조건 |
|------|------|
| `setupXcode` | `bundle.mode == .passthrough` |
| `installRelios` (Homebrew) | `dmgEnabled` 이거나 `bundle.mode == .assembly` |
| `installDMGBuild` (pip) | `dmgEnabled` |
| build 단계 | passthrough면 사용자 명령, assembly면 `relios release` |
| `keychainSetupBlock` + `keychainCleanupBlock` | `devIDSigning` |
| `dmgStepsBlock` (`relios dmg`) | `dmgEnabled` |
| `notarizeStepsBlock` (`relios notarize "$ARTIFACT"`) | `notarize` |
| `publishStep` files 목록 | `dmgEnabled`면 ZIP + DMG, 아니면 ZIP만 |

각 블록은 사이드 이펙트가 없고 순수 문자열 함수다. spec 조합이 늘어나도 다른 블록을 깨지 않는다.

**핀된 SHA를 정적 상수로 한 곳에 두는 이유.** `actions/checkout`, `maxim-lobanov/setup-xcode`, `softprops/action-gh-release`의 SHA가 파일 상단에 `checkoutSHA`/`setupXcodeSHA`/`ghReleaseSHA` 상수로 박혀 있다. `CIWorkflowRenderer`도 동일한 상수 이름을 쓴다. 업그레이드 시 두 파일의 한 줄씩만 바꾸면 모든 워크플로우 출력이 즉시 따라온다. 보안 측면에서도 태그(`@v6`)가 아닌 SHA를 쓰는 게 GitHub 권장이며, 한 곳에 모아두면 SHA 회전이 단일 PR로 끝난다.

CI environment readiness 규칙 자체(`GitHubRemoteRule`, `CIWorkflowPresenceRule`, `ReleaseWorkflowPresenceRule`)는 `CI/Rules/` 하위에 별도 슬라이스로 분리되어 있다 — Doctor가 일반 ValidationRule들과 함께 평가한다.

### 6.8 에러 도메인

슬라이스마다 자기 `*Error` enum을 갖는다. 12개 정도 있다:

```
Spec/SpecLoadError      Build/BuildError       Bundle/BundleError
Init/InitError          Signing/SigningError   DMG/DMGError
Notarize/NotarizeError  Install/InstallError   Rollback/RollbackError
Version/VersionSourceError                     CI/CIError
                  Release/ReleaseError  ← 위 도메인 에러를 catch&재포장
```

**공통 표면 패턴: `shortReason` + `shortFix`.** 모든 도메인 에러가 두 extension 프로퍼티를 노출한다:

```swift
extension BuildError {
    public var shortReason: String { /* "Build command exited with code 1: ..." */ }
    public var shortFix: String    { /* "Run with --verbose to see full build output" */ }
}
```

덕분에 CLI는 어떤 에러든 동일한 한 줄 포맷으로 출력할 수 있다:

```
[stage: <step>] failed: <shortReason>
  fix: <shortFix>
```

이 패턴 덕분에 `ConsoleReporter`는 12개 enum 각각을 switch 할 필요가 없다. 게다가 새 슬라이스가 추가될 때 `*Error`에 두 프로퍼티만 구현하면 자동으로 CLI 출력 포맷에 끼어든다 — 보일러플레이트는 있지만 결합도가 0이다.

**`ReleaseError`는 한 단계 더 나아간다.** 12 도메인 에러를 그대로 노출하지 않고, `ReleasePipeline`이 catch 해서 `ReleaseError.buildFailed(reason:fix:stderrTail:)` 같은 case로 재포장한다(`Release/ReleaseError.swift`). 이유: `relios release`가 실패했을 때 CLI는 `ReleaseError`만 switch 하면 되고, 어떤 도메인이 터졌는지를 모른 채로 일관된 출력을 낼 수 있다. `ReleaseError.step` 프로퍼티가 어느 `ReleaseStep`에서 죽었는지 알려주므로 `[stage: build] failed:` 같은 stage 라벨도 그냥 따라온다.

`stderrTail`을 따로 들고 다니는 case(`buildFailed`, `signingFailed`)는 codesign/swift build의 마지막 ~500바이트만 잘라서 운반한다. 전체 출력은 `--verbose`에서만 노출되고, 기본은 tail만 보여줘서 콘솔이 도배되지 않는다.

---

여기까지가 코드베이스 지도다. 사용자 입장의 명령어 사용법은 7장, 규칙 하나하나가 무엇을 검증하는지는 8장, 위 인터페이스들을 테스트가 어떻게 활용하는지는 9장으로 이어진다.
