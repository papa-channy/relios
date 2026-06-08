## 3. 핵심 개념

이 섹션은 Relios 전반에서 반복적으로 등장하는 용어와 개념을 정의합니다. TOML 필드의 세부 의미와 기본값은 Section 5(스펙)에서, 명령 사용법은 Section 4(CLI)에서 다룹니다. 여기서는 "이 단어가 어떤 모델을 가리키는가"와 "어떤 모드에서 어떤 단계가 활성/생략되는가"에만 집중합니다.

### 3.1 프로젝트 타입 (Project Type)

`relios.toml`의 `[project].type`은 두 값만 허용합니다.

| 타입 | 빌드 도구 | 일반적인 출력 위치 | 기본 `bundle.mode` |
|---|---|---|---|
| `swiftpm` | `swift build` | `.build/release/<binary>` | `assembly` |
| `xcodebuild` | `xcodebuild` | `build/Build/Products/Release/<Name>.app` | `passthrough` |

타입은 `relios init`이 프로젝트 루트를 스캔해 자동으로 결정합니다. 판정 로직은 `Sources/ReliosCore/Init/ProjectScanner.swift`에 있으며 우선순위는 다음과 같습니다.

```
1. Xcode 마커가 하나라도 있는가? (.xcodeproj / .xcworkspace / project.yml)
     yes → type = xcodebuild
2. Package.swift가 있는가?
     yes → type = swiftpm
3. 둘 다 없으면
     → InitError.notSwiftPMProject 로 init 실패
```

Xcode 마커는 SwiftPM 마커보다 우선합니다. `Package.swift`와 `.xcodeproj`가 함께 있는 하이브리드 프로젝트(예: SwiftPM 패키지를 Xcode 워크스페이스에서 함께 여는 경우)는 `xcodebuild`로 분류됩니다. 이는 "Xcode 산출물을 받는 쪽이 SwiftPM 단순 빌드보다 더 많은 단계(서명/엔타이틀먼트)를 거치므로 보수적으로 후자를 채택한다"는 정책입니다.

`binary_target`은 `swiftpm`에서는 `Sources/<Name>/<Name>.swift`를 찾아 첫 매치, `xcodebuild`에서는 `.xcodeproj` 파일명의 확장자 제거 결과로 결정됩니다. 어느 경우든 실패 시 프로젝트 루트 디렉터리 이름으로 폴백합니다.

> 핵심: `[project].type`은 **빌드 단계를 어떻게 실행할지**만 결정합니다. "Relios가 .app을 만드는가, 받기만 하는가"는 다음 절의 `bundle.mode`가 결정합니다.

### 3.2 번들 모드 (Bundle Mode)

`[bundle].mode`는 .app 번들이 어디서 만들어지는지를 가리키는 핵심 스위치입니다. `Sources/ReliosCore/Spec/BundleSection.swift` 정의.

| 모드 | 누가 .app을 만드나 | Info.plist 생성 | 아이콘/리소스 복사 |
|---|---|---|---|
| `assembly` | Relios | Relios가 생성 | Relios가 복사 |
| `passthrough` | 사용자 빌드 명령 (보통 `xcodebuild`) | 이미 존재 (건드리지 않음) | 이미 존재 (건드리지 않음) |

#### 3.2.1 모드별 파이프라인 비교

```
                          assembly             passthrough
  ─────────────────────────────────────────────────────────
  1. preflight             O                    O
  2. read version          O                    O
  3. compute next ver      O                    O
  4. build (swift/xc)      O                    O
  5. verify artifact      binary               .app
  6. write version src     O                    O
  7. assemble .app         O                    SKIP
  8. write Info.plist      O                    SKIP
  9. sign                  O (mode따라)         O (mode따라)
 10. backup existing       O                    O
 11. terminate running     O                    O
 12. install               O                    O
 13. launch                O                    O
 14. write manifest        O                    O
```

`passthrough`는 Xcode가 이미 만든 .app을 그대로 사용한다는 약속이므로 7–8단계(번들 조립, Info.plist 생성)를 건너뜁니다. 따라서 `[app].min_macos`, `[assets].icon_path`, `[app].copyright` 같은 필드는 `passthrough`에서 **읽히지 않습니다** — Info.plist는 Xcode가 이미 박아둔 것이 그대로 살아남습니다.

`relios init`은 `xcodebuild` 프로젝트를 감지하면 `bundle.mode = "passthrough"`를 기본값으로 적습니다. SwiftPM 프로젝트는 `assembly`가 기본입니다.

### 3.3 서명 모드 (Signing Mode)

`[signing].mode`는 codesign을 어떻게 호출할지 결정합니다. `Sources/ReliosCore/Spec/SigningSection.swift` 정의.

| 모드 | codesign 호출 형태 | 추가 요구 필드 | 노타라이즈 가능 | 게이트키퍼 통과 |
|---|---|---|---|---|
| `adhoc` | `codesign --force --deep --sign -` | 없음 | 불가 | 로컬 실행만 가능 |
| `keep` | (호출 안 함) | 없음 | 호출 측 책임 | Xcode가 한 서명에 따름 |
| `developer-id` | `codesign --force --deep --timestamp --options runtime --sign '<identity>'` | `identity`, `team_id` | 가능 | 가능 (노타라이즈 후) |

#### 3.3.1 모드별 의미

- **`adhoc`** — Apple Developer 계정이 없거나 로컬에서만 굴릴 때. 서명 식별자가 `-`이라 게이트키퍼는 "확인되지 않은 개발자" 또는 "손상되었거나 불완전합니다"를 띄웁니다. 노타라이즈는 **불가능**합니다.
- **`keep`** — `passthrough` 모드와 짝으로 자주 쓰입니다. Xcode가 빌드 시점에 이미 서명을 박았으므로 Relios가 다시 덮어쓰면 인증서/엔타이틀먼트가 어긋날 위험이 있습니다. Relios는 서명 단계를 통째로 건너뛰고, 검증은 `relios doctor` 및 노타라이즈 시점에 위임합니다.
- **`developer-id`** — Apple Developer Program ($99/year)에서 발급받은 "Developer ID Application" 인증서로 서명합니다. `identity`(예: `"Developer ID Application: Chan (ABCDE12345)"`)와 `team_id`(괄호 안 10자) 두 필드가 반드시 필요하며, `hardened_runtime = true`(기본값)일 때만 노타라이즈 대상이 됩니다.

#### 3.3.2 `hardened_runtime` 기본값이 true인 이유

Hardened Runtime이 꺼진 바이너리는 사실상 노타라이즈가 거부됩니다. 그래서 `SigningSection.init`은 이 필드를 명시하지 않으면 `true`를 적용합니다. 로컬 디버깅 등 특수 상황에서만 명시적으로 `false`를 설정하세요.

### 3.4 노타라이제이션 (Notarization)

서명과 노타라이제이션은 자주 혼동되지만 답하는 질문이 다릅니다.

| 질문 | 담당 |
|---|---|
| "누가 만들었는가?" — 출처 증명 | **코드 서명** (Developer ID 인증서) |
| "Apple이 검사한 결과 악성 코드가 없는가?" — 통과 증명 | **노타라이제이션** (Apple Notary Service) |

둘은 직렬로 묶여 있습니다. 노타라이즈하려면 먼저 Developer ID로 서명되어 있어야 하고, 서명만 해도 게이트키퍼 첫 실행 UX는 여전히 거칩니다. 차이를 정리하면 다음과 같습니다.

```
+---------------------------+--------------------------------------------+
| 상태                       | 첫 실행 시 macOS UX                         |
+---------------------------+--------------------------------------------+
| adhoc 서명만               | "손상되었거나 불완전합니다" → 휴지통 권유      |
| dev-id 서명만 (no notarize)| "확인되지 않은 개발자" → 설정 > 보안 우회 필요  |
| dev-id + 노타라이즈 + staple| "다운로드한 앱입니다. 열겠습니까?" → 한 번만 묻고 끝 |
+---------------------------+--------------------------------------------+
```

#### 3.4.1 노타라이즈 파이프라인

`Sources/ReliosCore/Notarize/Notarizer.swift`에서 다음 순서로 진행합니다.

```
1. xcrun notarytool submit <artifact> --wait
     (Apple 서버 큐: 일반적으로 5~45분, 최악의 경우 1시간+)
2. .dmg 인 경우  → xcrun stapler staple <artifact>
   .zip 인 경우  → unzip → 내부 .app에 staple → ditto 로 재압축
3. xcrun stapler validate (paranoid check)
```

#### 3.4.2 스테이플(staple)이란

Apple Notary Service가 "이 빌드는 통과"라고 발급한 티켓을 산출물에 **물리적으로 박는 작업**입니다. 스테이플이 박혀 있으면 사용자 머신이 오프라인이어도 게이트키퍼가 통과 여부를 확인할 수 있습니다.

- `.app`, `.dmg`, `.pkg` — 직접 스테이플 가능
- `.zip` — **스테이플 불가**. 압축을 풀고 내부 `.app`에 스테이플한 뒤 다시 zip으로 묶습니다 (위 2번 단계)

`relios notarize`는 산출물 확장자를 보고 두 경로 중 하나를 자동 선택합니다. Apple의 CDN이 "Accepted" 응답 직후 일시적으로 티켓을 못 찾는 경우가 있어 `stapler staple`이 exit code 65/66을 내면 10초 간격으로 3회까지 재시도합니다.

### 3.5 버전 소스 (Version Source)

Relios는 빌드/Info.plist에 박을 버전을 **Swift 소스 파일에서 정규식으로 읽고 씁니다**. Xcode의 Marketing Version이나 별도 JSON이 아닌, 코드 자체가 진실의 단일 출처입니다.

#### 3.5.1 표준 형태

```swift
// AppVersion.swift
enum AppVersion {
    static let current = "0.3.1"
    static let build   = "42"
}
```

`[version]` 섹션은 세 필드로 이 파일을 가리킵니다.

```toml
[version]
source_file     = "Sources/MyApp/AppVersion.swift"
version_pattern = "static let current\\s*=\\s*\"([^\"]+)\""
build_pattern   = "static let build\\s*=\\s*\"([^\"]+)\""
```

`version_pattern`과 `build_pattern`은 반드시 **캡처 그룹 한 개**가 있어야 합니다. `VersionSourceReader`는 첫 캡처만 사용합니다(`Sources/ReliosCore/Version/VersionSourceReader.swift`). 캡처가 없거나 패턴이 매치되지 않으면 `relios doctor`와 `relios release`가 모두 실패합니다.

#### 3.5.2 읽기/쓰기 분리

```
                  read                 write
  ─────────────────────────────────────────────────────
  doctor          O (검증)              X
  release --dry   O                     X (Gate 5 invariant)
  release         O → compute next →    O (bump 적용)
  inspect         X                     X (manifest만 봄)
```

`--dry-run`은 절대 소스 파일을 건드리지 않습니다. 이 보장은 `ReleasePipeline.run`에서 6단계(`updateVersionSource`)가 dry-run 분기 뒤에 위치해 구조적으로 강제됩니다.

#### 3.5.3 bump 규칙

- `--bump none`(기본) — 버전 유지, build만 +1
- `--bump patch|minor|major` — semver 해당 자리 +1, build는 `1`로 리셋

### 3.6 릴리스 매니페스트 & 백업

릴리스 한 번이 끝날 때마다 Relios는 두 가지를 남깁니다.

```
프로젝트루트/
└── dist/
    ├── <AppName>.app              ← 방금 만든 (혹은 받은) 번들
    ├── releases/
    │   ├── latest.json            ← 항상 가장 최근 릴리스
    │   └── history/
    │       ├── 2025-05-20T09-31-12Z.json
    │       └── 2025-05-25T14-02-44Z.json
    └── app-backups/
        ├── MyApp-v0.3.0-b41.zip   ← 이번 릴리스 직전에 설치되어 있던 .app
        └── MyApp-v0.2.9-b40.zip
```

#### 3.6.1 매니페스트(`latest.json`)

`Sources/ReliosCore/Release/ReleaseManifest.swift` 정의. JSON 키는 snake_case로 인코딩됩니다.

| 필드 | 의미 |
|---|---|
| `app_name`, `bundle_id` | 식별자 |
| `version`, `build` | 이번 릴리스가 기록한 값 |
| `bundle_path` | `dist/<AppName>.app` 절대 경로 |
| `install_path` | 설치된 위치 (보통 `/Applications/...`) |
| `backup_path` | 이번에 만든 백업 zip 경로 (없으면 null) |
| `signing_mode` | `adhoc` / `keep` / `developer-id` |
| `bundle_mode` | `assembly` / `passthrough` |
| `launched_after_install` | `auto_open` 결과 |
| `timestamp` | ISO8601 |

`latest.json`은 매 릴리스마다 덮어쓰고, `history/<timestamp>.json`은 추가만 됩니다. `relios inspect`는 `latest.json` 한 파일만 읽습니다(`InspectReader`).

#### 3.6.2 백업(`app-backups/`)

새 .app을 설치하기 직전에 **현재 설치되어 있던** .app을 zip으로 묶어 보관합니다. 파일명은 `<AppName>-v<prev_version>-b<prev_build>.zip` 형태로, 알파벳 순 정렬이 곧 시간순 정렬이 되도록 설계되어 있습니다(`BackupManager.swift`).

- `[install].keep_backups`개를 초과하면 가장 오래된 백업부터 삭제됩니다 (정렬 기준은 파일명).
- `relios release --skip-backup`을 주면 백업 단계가 건너뛰어집니다 (manifest의 `backup_path`는 null).
- `relios rollback`은 `backup_dir`에서 가장 최근 zip을 풀어 `install_path`에 다시 펼칩니다(`RollbackRunner.swift`).

### 3.7 디렉터리 구조 규약

Relios가 생성/관리하는 경로와 사용자 프로젝트의 경로는 명확히 구분됩니다.

```
프로젝트루트/                       ← 사용자 소유 (commit 대상)
├── Package.swift  또는  *.xcodeproj
├── Sources/...                    ← 사용자 코드, AppVersion.swift 포함
├── relios.toml                    ← 사용자 작성/편집
├── .github/workflows/
│   ├── ci.yml                     ← relios ci init 이 생성, 이후 사용자 소유
│   └── release.yml                ← 동일
│
└── dist/                          ← Relios 소유 (.gitignore 권장)
    ├── <AppName>.app              ← 매 릴리스마다 재생성
    ├── <AppName>-<version>.dmg    ← [dmg].enabled 일 때
    ├── releases/
    │   ├── latest.json
    │   └── history/<ts>.json
    └── app-backups/
        └── <AppName>-v*-b*.zip
```

원칙:

- `dist/` **아래는 모두 Relios의 영토**입니다. 사람이 수정하면 다음 릴리스에 덮어쓰여집니다. `.gitignore`에 `dist/`를 추가하는 것을 권장합니다.
- `relios.toml`, `Sources/`, `.github/workflows/`는 **사용자의 영토**입니다. Relios는 명시적 명령(`relios init`, `relios ci init --force`)이 있을 때만 이 영역을 건드립니다.
- 설치 결과(`/Applications/<Name>.app`)는 사용자 시스템에 속하며 프로젝트 디렉터리 밖에 있습니다. `relios rollback`만이 이 경로를 다시 변경합니다.

### 3.8 CI 워크플로우 자동 분기 규칙

`relios ci init`은 `relios.toml`을 읽어 그 시점의 설정에 맞는 `release.yml`을 생성합니다. 어떤 섹션이 켜져 있느냐에 따라 스텝과 secrets 요구사항이 추가됩니다. 분기 로직은 `Sources/ReliosCore/CI/ReleaseWorkflowRenderer.swift`에 모여 있습니다.

#### 3.8.1 분기 매트릭스

| 활성 조건 | 추가되는 워크플로우 스텝 | 추가로 요구되는 GitHub Secrets |
|---|---|---|
| 항상 | `checkout` → `build` → `verify` → `Package .app`(zip) → `Publish GitHub Release` | (없음) |
| `[bundle].mode = "passthrough"` | `setup-xcode@v1.7.0` (라테스트 스테이블 Xcode 픽업) | (없음) |
| `[bundle].mode = "assembly"` | `Install Relios` (Homebrew) — `relios release` 호출용 | (없음) |
| `[signing].mode = "developer-id"` | `Import Developer ID certificate` (키체인 import) + `Delete signing keychain` (`if: always()` cleanup) | `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` |
| `[dmg].enabled = true` | `Install dmgbuild` (pip), `Create DMG` (`relios dmg`), `Record DMG path` (`DMG_FILE` env) — 또한 `Install Relios` 자동 활성 | (없음) |
| `[notarize].enabled = true` | `Notarize + staple` (`relios notarize "$ZIP"` 또는 `"$DMG_FILE"`) | `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` |

#### 3.8.2 조합 예시

```
relios.toml                              생성되는 release.yml의 모양
─────────────────────────────────────────────────────────────────────
bundle.mode = assembly                   checkout → install relios →
signing.mode = adhoc                       build → verify → zip →
(dmg, notarize 없음)                       publish

bundle.mode = passthrough                checkout → setup-xcode →
signing.mode = keep                        xcodebuild → verify → zip →
(dmg, notarize 없음)                       publish

bundle.mode = assembly                   checkout → import cert →
signing.mode = developer-id                install relios → install dmgbuild →
dmg.enabled = true                         relios release → verify → zip →
notarize.enabled = true                    relios dmg → record DMG path →
                                           relios notarize $DMG_FILE →
                                           publish (zip + dmg) →
                                           delete keychain (always)
```

#### 3.8.3 노타라이즈 산출물 선택

`relios notarize`는 인자 없이도 동작하지만, CI에서는 명시적 경로를 넘깁니다. 이유는 산출물 이름이 git tag에서 만들어지기 때문에 `AppVersion.swift`의 버전과 어긋날 수 있어서, 자동 추론에 맡기면 잘못된 파일을 찾을 수 있기 때문입니다. 따라서 CI 워크플로우는 `$DMG_FILE`(DMG 우선)이나 `$ZIP`을 명시적으로 전달합니다(`ReleaseWorkflowRenderer.notarizeStepsBlock`).

#### 3.8.4 재생성 정책

`relios ci init`은 이미 `release.yml`/`ci.yml`이 존재하면 기본적으로 덮어쓰지 않습니다. `--force` 플래그로 강제 재생성할 수 있으며, 사용자가 수동 편집한 내용은 그 시점에 모두 사라집니다. 따라서 워크플로우를 손으로 다듬은 뒤에는 `relios.toml`을 바꿔도 `--force`를 주기 전까지 워크플로우는 그대로 유지됩니다.

> 다음 절(Section 4)에서는 이 개념들을 실제로 호출하는 서브커맨드(`init`, `doctor`, `release`, `dmg`, `notarize`, `rollback`, `ci init`)의 사용법을 다룹니다.
