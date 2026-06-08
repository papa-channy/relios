## 8. Doctor 규칙과 문제 진단

이 섹션은 `relios doctor`와 `relios ci doctor`가 어떤 규칙을 어떤 순서로 실행하는지, 각 규칙이 실패할 때 출력되는 reason/fix 메시지의 의미는 무엇인지, 그리고 실무에서 자주 마주치는 실패 시나리오를 어떻게 해결하는지를 다룹니다. 규칙의 실제 검사 로직과 메시지 문구는 모두 `Sources/ReliosCore/Validation/Rules/`, `Sources/ReliosCore/CI/Rules/`, 그리고 `Sources/ReliosCLI/Commands/`의 구현에서 그대로 인용했습니다.

명령의 일반적인 사용법(플래그, 표준 동작, 출력 포맷)은 Section 4를 참고하고, 워크플로우 전체에서 Doctor가 어디에 위치하는지는 Section 7을 참고하세요.

### 8.1 Doctor 시스템 개요

#### 8.1.1 두 가지 Doctor

Relios는 검사 대상에 따라 두 개의 Doctor를 분리해서 제공합니다.

| 명령 | 검사 대상 | 규칙 위치 |
|---|---|---|
| `relios doctor` | 로컬 머신에서 release/sign/dmg/notarize가 가능한 상태인지 | `ReliosCore/Validation/Rules/` |
| `relios ci doctor` | GitHub Actions가 release를 트리거하고 실행할 수 있는 상태인지 | `ReliosCore/CI/Rules/` |

두 명령 모두 진입 시 `relios.toml`을 `SpecLoader`로 로드합니다. 로드 자체가 실패하면 (TOML 구문 오류, 필수 키 누락 등) 규칙 평가는 시작되지 않고 `[fail] spec load`와 함께 `SpecLoadError`의 `shortReason`/`shortFix`가 출력된 뒤 exit 1로 종료됩니다.

#### 8.1.2 규칙 결과 유형

각 규칙은 `RuleResult` enum의 세 가지 케이스 중 하나를 반환하고, `DoctorRunner`가 이를 `Diagnostic.Status`로 평탄화합니다.

| 결과 | 의미 | 출력 prefix | 종료 코드 영향 |
|---|---|---|---|
| `.ok(title)` | 검사 통과 | `[ok]` | 없음 |
| `.warn(title, reason, fix)` | 권장 사항 미충족, 진행은 가능 | `[warn]` | 없음 |
| `.fail(title, reason, fix)` | 다음 단계가 확실히 실패할 조건 | `[fail]` | 단 하나라도 있으면 exit 1 |

`.ok`는 reason/fix를 갖지 않습니다. `.warn`과 `.fail`은 항상 reason과 fix를 함께 출력하므로, 사용자는 "왜 실패했는가"와 "어떻게 고칠 것인가"를 한 화면에서 확인할 수 있습니다.

#### 8.1.3 종합 상태(Status)

규칙 전체 평가가 끝나면 다음 규칙으로 한 줄 요약이 추가됩니다 (`DoctorCommand.printSummary` 기준).

| 조건 | Status |
|---|---|
| `.fail`이 한 건이라도 있음 | `not ready` |
| `.fail`은 없고 `.warn`만 있음 | `mostly ready` |
| 전부 `.ok` | `ready` |

#### 8.1.4 Exit code

`.fail`이 하나라도 포함되면 `DoctorCommand`/`DoctorSubcommand`는 `ExitCode.failure`(exit 1)를 던집니다. `.warn`만 있는 경우는 exit 0입니다. 이는 CI 파이프라인의 `relios doctor` 게이트를 설계할 때 핵심입니다 — warn은 통과시키되 fail은 즉시 차단하는 표준 동작이 별도 후처리 없이 적용됩니다.

---

### 8.2 `relios doctor`에서 실행되는 규칙들

`DoctorCommand.run()`은 다음 8개 규칙을 정확히 이 순서로 실행합니다.

```
XcodeProjectGuardRule
SpecValidityRule
VersionSourceRule
BuildReadinessRule
InstallPathRule
SigningReadinessRule
DMGReadinessRule
NotarizeReadinessRule
```

순서는 의미가 있습니다 — 앞쪽 규칙이 실패해도 뒤쪽 규칙은 계속 평가되지만, 통상 "프로젝트 구조 → 스펙 유효성 → 빌드 도구 → 출력 경로 → 서명 → DMG → 노타라이즈" 순으로 결과를 읽으면 의존 관계가 자연스럽게 드러납니다.

#### 8.2.1 XcodeProjectGuardRule

구현: `Sources/ReliosCore/Validation/Rules/XcodeProjectGuardRule.swift`

**검사 내용**: 프로젝트 루트에 Xcode 마커 파일(`*.xcodeproj`, `*.xcworkspace`, `project.yml`)이 존재하는지 스캔하고, 존재한다면 `[bundle].mode`가 `passthrough`인지 확인합니다. assembly 모드는 Relios가 `.app`을 처음부터 조립하는 방식이라 `xcodebuild`가 이미 완성된 `.app`을 만드는 Xcode 프로젝트와 충돌합니다.

**Skip 조건**: 마커가 하나도 없으면 `.ok(title: "project type compatible")`. 마커가 있어도 `[bundle].mode == .passthrough`이면 `.ok(title: "project type compatible (passthrough)")` — 사용자가 명시적으로 "xcodebuild가 만든 .app을 그대로 받겠다"고 옵트인한 것이므로 통과.

**Fail reason 예시**:
> `Found MyApp.xcodeproj — Relios bundle assembly is incompatible with Xcode-managed projects`

**Fix**:
> `Set [bundle].mode = "passthrough" and [project].type = "xcodebuild" in relios.toml, or remove Xcode project files for pure SwiftPM.`

#### 8.2.2 SpecValidityRule

구현: `Sources/ReliosCore/Validation/Rules/SpecValidityRule.swift`

**검사 내용**: 디코딩은 성공했지만 의미적으로 비어 있는 필수 필드를 잡습니다. v1에서는 세 가지만 검사합니다 — `[app].name`, `[app].bundle_id`, `[project].binary_target`. bundle id 포맷 검증이나 `min_macos` 파싱 가능성 같은 깊은 검사는 별도 규칙으로 분리될 예정입니다.

**Skip 조건**: 없음. 항상 실행됩니다.

**Fail reason 예시 (세 가지)**:
- `Application name must not be empty` → Fix: `Set [app].name in relios.toml`
- `Bundle identifier is required` → Fix: `Set [app].bundle_id in relios.toml`
- `No executable target specified` → Fix: `Set [project].binary_target in relios.toml`

#### 8.2.3 VersionSourceRule

구현: `Sources/ReliosCore/Validation/Rules/VersionSourceRule.swift`

**검사 내용**: `[version].source_file`이 가리키는 파일이 존재하고, `version_pattern`과 `build_pattern`이 그 파일에서 각각 한 번 이상 매치되는지를 `VersionSourceReader`로 read-only 시도합니다. 이 규칙은 "false-ready 문제"의 해결책입니다 — 도입 전에는 `AppVersion.swift`가 없어도 doctor가 ready라고 답해버려서 release 단계의 버전 읽기에서 실패했습니다.

**Skip 조건**: 없음.

**Fail reason 예시**:
- 파일 부재: `Sources/MyApp/AppVersion.swift not found at /Users/me/proj/Sources/MyApp/AppVersion.swift` → Fix: `Create the file or update [version].source_file in relios.toml`
- 패턴 불일치: `VersionSourceError.shortReason`이 그대로 노출 (예: 정규식이 어떤 캡처도 찾지 못함) → Fix: `VersionSourceError.shortFix` 사용

#### 8.2.4 BuildReadinessRule

구현: `Sources/ReliosCore/Validation/Rules/BuildReadinessRule.swift`

**검사 내용**: `[project].type`에 맞는 빌드 도구가 PATH에 있는지 `which <tool>`로 확인합니다.

| `project.type` | 검사 도구 | Fix |
|---|---|---|
| `swiftpm` | `swift` | `Install Xcode Command Line Tools: xcode-select --install` |
| `xcodebuild` | `xcodebuild` | `Install Xcode from the Mac App Store, then run sudo xcode-select --switch /Applications/Xcode.app. Command Line Tools alone do not include xcodebuild.` |

**Skip 조건**: `ValidationContext.process`가 nil(`.ok(title: "build tool check skipped")`). 정상 CLI 실행 경로에서는 `RealProcessRunner`가 주입되므로 실질적으로 스킵되지 않습니다.

**Fail reason 예시**: `\`xcodebuild\` is not in PATH`

#### 8.2.5 InstallPathRule

구현: `Sources/ReliosCore/Validation/Rules/InstallPathRule.swift`

**검사 내용**: `[install].path`의 부모 디렉터리가 디렉터리로 존재하는지 확인합니다. 이 규칙은 의도적으로 fail이 아니라 **warn**을 반환합니다 — release 시점에 디렉터리가 생성되거나 사용자가 `--install-path`로 오버라이드할 수 있기 때문입니다.

**Skip 조건**: 없음.

**Warn reason 예시**:
> `Directory /Applications does not exist`

**Fix**:
> `Create the directory or update [install].path in relios.toml`

#### 8.2.6 SigningReadinessRule

구현: `Sources/ReliosCore/Validation/Rules/SigningReadinessRule.swift`

**검사 내용**: `[signing].mode`에 따라 단계적으로 검사합니다.

| 모드 | 검사 항목 |
|---|---|
| `keep` | 검사 없음 — `.ok(title: "signing skipped (keep mode)")` |
| `adhoc` | `codesign`이 PATH에 있는지만 검사 |
| `developer-id` | `codesign` + `[signing].identity` 비어 있지 않음 + `[signing].team_id` 비어 있지 않음 + `security find-identity -v -p codesigning` 출력에 identity 문자열 또는 `(team_id)` 포함 |

**Skip 조건**: `mode == .keep`인 경우 전체 스킵. `ValidationContext.process`가 nil인 경우 codesign/keychain 검사 스킵.

**Fail reason 예시들**:
- identity 누락: `mode = "developer-id" requires [signing].identity` → Fix: `Run \`relios signing setup\` or set signing.identity in relios.toml`
- team_id 누락: `mode = "developer-id" requires [signing].team_id` → Fix: `Run \`relios signing setup\` or set signing.team_id in relios.toml`
- codesign 부재: `\`codesign\` is not in PATH` → Fix: `Install Xcode Command Line Tools: xcode-select --install`
- keychain 부재: `neither "Developer ID Application: ..." nor team ABCDE12345 appeared in \`security find-identity\`` → Fix: `Import the cert: \`relios signing import <path-to.p12>\` or install via Xcode`

키체인 검사는 identity 문자열 매치와 `(team_id)` 매치 중 **하나라도** 성공하면 통과시킵니다. 사용자가 identity 이름을 부정확하게 적었어도 같은 팀 인증서가 있으면 통과시키는 관대한 정책입니다.

#### 8.2.7 DMGReadinessRule

구현: `Sources/ReliosCore/Validation/Rules/DMGReadinessRule.swift`

**검사 내용**: `[dmg]` 섹션이 활성화되어 있다면 `dmgbuild`가 PATH에 있는지 `command -v dmgbuild`로 확인합니다.

**Skip 조건**: `[dmg]`가 없거나 `enabled = false`(`.ok(title: "dmg check skipped (disabled)")`).

**결과 수준은 warn**: DMG는 선택적 산출물이고, 없어도 release 파이프라인의 나머지 단계는 동작합니다. 그래서 fail이 아니라 warn입니다.

**Warn reason 예시**:
> `\`dmgbuild\` is not in PATH; \`relios dmg\` will fail until it is installed`

**Fix**:
> `Install it: \`pip install dmgbuild\` (or \`pipx install dmgbuild\`)`

#### 8.2.8 NotarizeReadinessRule

구현: `Sources/ReliosCore/Validation/Rules/NotarizeReadinessRule.swift`

**검사 내용**: `[notarize]`가 활성화되어 있을 때 다음을 순서대로 검사합니다.

1. `[signing].mode == .developerID` — 노타라이즈는 Developer ID 서명을 전제로 합니다. ad-hoc 바이너리는 노타라이즈할 수 없습니다. **fail**.
2. `xcrun notarytool --version` 실행 가능 여부 — Xcode 13+가 필요합니다. Command Line Tools만으로는 notarytool이 포함되지 않습니다. **fail**.
3. `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` 환경 변수 비어 있지 않은지 — 로컬에서는 흔히 비어 있고 CI에서는 secrets로 주입되므로 **warn**.
4. `[signing].team_id`와 `APPLE_TEAM_ID`가 둘 다 존재할 때 같은 값인지 — Apple은 서명자 팀과 제출자 팀이 다르면 거절합니다. **warn**.

**Skip 조건**: `[notarize]`가 없거나 `enabled = false`.

**Fail reason 예시**:
- 서명 모드 불일치: `[notarize].enabled = true requires [signing].mode = "developer-id" (current: "adhoc")` → Fix: `Change [signing].mode to "developer-id" — notarization cannot be applied to ad-hoc binaries`
- notarytool 부재: `\`xcrun notarytool\` did not run (exit 72)` → Fix: `Install Xcode 13+ (Command Line Tools alone don't include notarytool)`

**Warn reason 예시**:
- env 누락: `missing env: APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD` → Fix: `Set them before running \`relios notarize\`, or supply them via GitHub secrets in CI`
- team 불일치: `[signing].team_id (ABCDE12345) ≠ APPLE_TEAM_ID (FGHIJ67890)` → Fix: `Align the two — Apple rejects submissions where the signer's team differs from the submitter's`

---

### 8.3 `relios ci doctor`에서 실행되는 규칙들

`CICommand.DoctorSubcommand.run()`은 다음 3개 규칙을 실행합니다.

```
ReleaseWorkflowPresenceRule
CIWorkflowPresenceRule
GitHubRemoteRule
```

검사 범위는 "GitHub이 release를 트리거하고 실행할 수 있는 최소 조건"으로 좁아져 있습니다. 빌드/서명/노타라이즈 가능성은 `relios doctor`가 별도로 확인하므로 중복 검사하지 않습니다.

#### 8.3.1 ReleaseWorkflowPresenceRule

구현: `Sources/ReliosCore/CI/Rules/ReleaseWorkflowPresenceRule.swift`

**검사 내용**: `.github/workflows/release.yml`이 존재하는지. 이 파일이 없으면 태그를 푸시해도 아무것도 동작하지 않습니다.

**Fail reason**:
> `.github/workflows/release.yml not found`

**Fix**:
> `Run \`relios ci init\` to generate it`

#### 8.3.2 CIWorkflowPresenceRule

구현: `Sources/ReliosCore/CI/Rules/CIWorkflowPresenceRule.swift`

**검사 내용**: `.github/workflows/ci.yml`이 존재하는지. PR/푸시 시점 CI 게이트는 편의 기능일 뿐 release 자체에는 영향이 없으므로 **warn**입니다.

**Warn reason**:
> `.github/workflows/ci.yml not found`

**Fix**:
> `Run \`relios ci init\` to regenerate (use --force if release.yml already exists)`

#### 8.3.3 GitHubRemoteRule

구현: `Sources/ReliosCore/CI/Rules/GitHubRemoteRule.swift`

**검사 내용**: 프로젝트가 git 저장소인지 확인하고(`.git/config` 존재 여부), 그 파일 내용에 `github.com` 문자열이 포함되어 있는지 검사합니다. 둘 다 **warn**입니다 — git 없이도 로컬 release는 동작하지만 GitHub Actions release는 불가능합니다.

구현 노트: `git` CLI를 호출하지 않고 `.git/config`를 직접 읽습니다. 그래서 PATH에 `git`이 없어도 동작하고, 단위 테스트가 순수 파일시스템만으로 가능합니다.

**Warn reason 예시**:
- 비-git: `Not a git repository (/Users/me/proj)` → Fix: `Run \`git init\` and add a GitHub remote before pushing tags`
- non-github remote: `No github.com remote found in .git/config` → Fix: `Add a GitHub remote: \`git remote add origin https://github.com/<you>/<repo>.git\``

---

### 8.4 흔한 실패 시나리오와 해결

#### 8.4.1 빠른 참조 표

| 증상 (메시지 일부) | 원인 | 해결 |
|---|---|---|
| `signing.team_id missing` | `mode = "developer-id"`인데 `[signing].team_id` 비어 있음 | `relios signing setup` 또는 `relios.toml`에 직접 기입 |
| `signing.identity missing` | 위와 동일하지만 identity 누락 | `relios signing setup` 또는 직접 기입 |
| `signing identity not found in keychain` | identity 문자열과 team_id 둘 다 keychain에 없음 | `relios signing import path-to.p12` 또는 Xcode > Settings > Accounts에서 Manage Certificates |
| `dmgbuild not found` | DMG 활성 상태인데 `dmgbuild` 부재 | `pip install dmgbuild` 또는 `pipx install dmgbuild` |
| `notarytool not available` | Xcode CLT만 설치되어 있음 | App Store에서 풀 Xcode 설치 후 `sudo xcode-select --switch /Applications/Xcode.app` |
| `notarize requires developer-id signing` | `[notarize].enabled = true`인데 `signing.mode != developer-id` | `[signing].mode = "developer-id"`로 변경 |
| `team_id mismatch` | `APPLE_TEAM_ID` 환경 변수가 `[signing].team_id`와 다름 | 둘 중 하나를 다른 쪽에 맞춰 정렬 |
| `Workflow already exists at ...` | 기존 워크플로우 파일 존재 (`relios ci init`) | `relios ci init --force` |
| `version source file missing` | `[version].source_file` 경로가 잘못됨 | 파일을 생성하거나 `[version].source_file` 수정 |
| `Xcode project detected with assembly mode` | `.xcodeproj` 옆에 `[bundle].mode = "assembly"` | `[bundle].mode = "passthrough"`로 변경하거나 Xcode 파일 제거 |

#### 8.4.2 Stapler exit 65/66

`xcrun notarytool`이 "Accepted"를 반환한 직후 `xcrun stapler staple`이 exit 65 또는 66으로 실패하는 경우입니다. 원인은 Apple CDN의 전파 지연 — 노타라이즈 티켓이 아직 stapler가 조회하는 엣지까지 도달하지 않은 상태입니다.

Relios는 `Notarizer.staple()`에서 이를 자동 처리합니다.

- 최대 3회 재시도
- 시도 사이 10초 대기
- exit code가 65 또는 66일 때만 재시도하고, 다른 코드는 즉시 실패로 던짐

3회 모두 실패하면 영구 실패로 간주합니다. 이 경우 `xcrun notarytool log <submission-id>`로 상세 원인을 확인해야 합니다 — 드물게 Apple 측 인덱싱 문제로 더 긴 지연이 발생하기도 합니다.

#### 8.4.3 Notarization이 30분 이상 걸림

Apple의 노타라이즈 큐 지연이 길어지는 경우입니다. 대부분 정상 범위(10~30분)이지만 새벽이나 OS 릴리스 직후에는 60분을 넘기도 합니다.

`[notarize].timeout_seconds`의 기본값은 3600초(60분)입니다 (`NotarizeSection.swift` 기준). 더 늘리려면 다음과 같이 설정합니다.

```toml
[notarize]
enabled = true
timeout_seconds = 5400  # 90분
```

`xcrun notarytool submit --wait --timeout <N>s`로 그대로 전달되므로, 큐 지연이 잦은 환경에서는 여유롭게 설정하는 편이 안전합니다. CI에서 디버깅이 어려우면 출력을 streaming하도록 변경된 동작 덕분에 큐 대기 상태를 실시간으로 확인할 수 있습니다.

#### 8.4.4 Notarization 결과가 "Invalid"

`xcrun notarytool`이 exit 0으로 끝났지만 stdout에 `status: Invalid` 또는 `status: Rejected`가 포함된 경우입니다. Relios는 `Notarizer`에서 키워드 스캔으로 이를 잡아 `NotarizeError.submissionFailed`를 던집니다.

원인 파악은 항상 `xcrun notarytool log <submission-id> --apple-id ... --team-id ... --password ...`로 시작합니다. 로그에는 거절 사유가 JSON으로 들어 있습니다. 흔한 원인은 다음과 같습니다.

| 원인 | 로그에 나타나는 키워드 | 해결 |
|---|---|---|
| Hardened Runtime 누락 | `The binary is not signed with a valid Developer ID certificate` 또는 `The executable does not have the hardened runtime enabled` | `[signing].mode = "developer-id"` 확인, codesign 옵션에 `--options runtime` 포함되었는지 확인 |
| 비공개/금지 entitlement 사용 | `The entitlement com.apple.private.* is not allowed` | 해당 entitlement 제거 |
| 서명되지 않은 dylib/framework 포함 | `The signature of the binary is invalid` (특정 dylib 경로 명시) | 번들 내 모든 동적 라이브러리에 codesign 적용 |
| 만료된/취소된 인증서 | `The signing certificate has expired` | Developer Portal에서 인증서 재발급 후 `relios signing import` |

#### 8.4.5 권장 디버깅 순서

문제가 생겼을 때 권장하는 디버깅 순서는 다음과 같습니다.

1. `relios doctor`로 로컬 환경 전체를 한 번 훑어 fail/warn 목록을 확보합니다. 종합 상태가 `not ready`라면 그 fail부터 해결합니다.
2. CI 실패라면 `relios ci doctor`도 추가로 실행해 워크플로우 파일과 GitHub remote 상태를 확인합니다.
3. doctor가 전부 ok인데도 release가 실패하면, 실패한 단계의 명령을 단독으로 실행합니다 (예: `relios sign`, `relios dmg`, `relios notarize`). 단독 실행은 streaming 출력으로 진행 상황을 보여주므로 doctor로는 잡히지 않는 런타임 오류(권한 거부, 큐 지연, Apple 일시 장애 등)를 식별할 수 있습니다.
4. 노타라이즈 관련 실패는 항상 `xcrun notarytool log <id>`가 진실의 원천입니다. Relios의 에러 메시지는 stdout/stderr만 전달하므로, 거절 사유의 구조화된 정보는 log 명령으로만 얻을 수 있습니다.
