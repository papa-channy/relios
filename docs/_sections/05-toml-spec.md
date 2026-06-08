## 5. relios.toml 스펙

이 섹션은 `relios.toml`의 모든 섹션과 필드를 소스 코드(`Sources/ReliosCore/Spec/*.swift`)와 한 글자도 어긋나지 않게 정리합니다. 각 필드의 TOML 키, Swift 타입, 기본값, 필수 여부, 그리고 파이프라인 어느 단계에서 어떻게 소비되는지를 다룹니다. 개념 정의는 Section 3, 명령으로 채우는 방법은 Section 4, 설계 의도는 Section 6를 참고하세요.

스펙은 최상위 `ReleaseSpec` 하나로 통합되며, 구성은 다음과 같습니다.

| 섹션 | 타입 | 필수 여부 | 비고 |
|---|---|---|---|
| `[app]` | `AppSection` | 필수 | 필드 5개 모두 필수 |
| `[project]` | `ProjectSection` | 필수 | 필드 3개 모두 필수 |
| `[version]` | `VersionSection` | 필수 | 필드 3개 모두 필수 |
| `[build]` | `BuildSection` | 필수 | `resource_bundle_path`는 선택 |
| `[assets]` | `AssetsSection` | 필수 | 단일 필드 `icon_path`는 선택 |
| `[bundle]` | `BundleSection` | 필수 | `mode`는 기본값 `assembly` |
| `[install]` | `InstallSection` | 필수 | 필드 5개 모두 필수 |
| `[signing]` | `SigningSection` | 필수 | `mode`만 필수, 나머지는 선택 |
| `[dmg]` | `DMGSection?` | 선택 | 전체 섹션 누락 시 DMG 건너뜀 |
| `[notarize]` | `NotarizeSection?` | 선택 | 전체 섹션 누락 시 노타라이제이션 건너뜀 |

TOML 파싱은 `TOMLDecoder`로 수행되며, 파일 자체는 `SpecLoader.load(from:)`이 읽어 `ReleaseSpec`으로 디코딩합니다. 파일 부재는 `SpecLoadError.missing`, 읽기 실패는 `.unreadable`, 디코딩 실패는 `.malformed`로 표면화됩니다.

### 5.1 [app]

앱의 정체성을 정의합니다. 모든 필드가 필수이며, 디코더에 `decodeIfPresent`나 기본값이 없으므로 누락 시 `.malformed`로 실패합니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `name` | `name` | string | — | 필수 | 바이너리/번들 이름, ZIP 파일명, `pgrep` 대상 |
| `displayName` | `display_name` | string | — | 필수 | `CFBundleName`, `CFBundleDisplayName` |
| `bundleId` | `bundle_id` | string | — | 필수 | `CFBundleIdentifier`, 실행 중인 앱 종료 식별자 |
| `minMacOS` | `min_macos` | string | — | 필수 | `LSMinimumSystemVersion` |
| `category` | `category` | string | — | 필수 | `LSApplicationCategoryType` |

`name`은 `dist/<name>.app` 경로 추론, `ditto`로 만드는 `<name>-<tag>.zip` 파일명, 그리고 실행 중인 앱을 종료할 때 `executableName`으로 모두 쓰입니다. `bundleId`는 Info.plist의 `CFBundleIdentifier`로 사용되며, `install.quit_running_app = true`인 경우 같은 번들 ID로 실행 중인 프로세스를 식별합니다. `displayName`은 Finder/메뉴바에 표시되는 이름이라 `name`과 다르게 줄 수 있습니다. `min_macos`와 `category`는 Info.plist에 그대로 박히며, Relios는 형식을 검증하지 않습니다(타입은 string).

`SpecValidityRule`(doctor의 spec validity 체크)이 `name`, `bundleId`가 빈 문자열이 아닌지 확인합니다.

### 5.2 [project]

프로젝트의 빌드 도구 유형과 루트, 그리고 바이너리 타겟을 정의합니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `type` | `type` | enum (`swiftpm` \| `xcodebuild`) | — | 필수 | `BuildReadinessRule`에서 도구 선택, CI 워크플로 분기 |
| `root` | `root` | string | — | 필수 | 모든 상대 경로의 기준 디렉터리 |
| `binaryTarget` | `binary_target` | string | — | 필수 | `SpecValidityRule`이 빈 문자열 여부 확인 |

`type`은 enum이라 `swiftpm` 또는 `xcodebuild` 두 값만 허용되며, 다른 값은 디코딩 단계에서 실패합니다. `BuildReadinessRule`은 이 값에 따라 `swift` 또는 `xcodebuild` 실행 파일의 PATH 존재 여부를 점검합니다. `CIWorkflowRenderer`도 동일한 분기를 사용해 GitHub Actions 워크플로를 다르게 렌더링합니다.

`root`는 일반적으로 `"."`이고, 모든 파일 경로(`bundle.output_path`, `build.binary_path`, `version.source_file`, `assets.icon_path`, `install.backup_dir`)는 이 루트를 기준으로 결합됩니다. `binary_target`은 SwiftPM의 executable target 이름과 동일해야 빌드 결과 위치 추론이 일관됩니다.

### 5.3 [version]

버전 문자열을 어디서 읽고 어떻게 파싱할지 정의합니다. Relios는 코드 안의 패턴을 신뢰원으로 사용해 같은 파일을 다시 써서 bump하는 구조입니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `sourceFile` | `source_file` | string | — | 필수 | 버전 읽기/쓰기 대상 파일 |
| `versionPattern` | `version_pattern` | string (regex) | — | 필수 | semver 캡처 정규식 |
| `buildPattern` | `build_pattern` | string (regex) | — | 필수 | build 번호 캡처 정규식 |

각 패턴은 정확히 하나의 캡처 그룹 `(.*)`을 가져야 하며, `VersionSourceReader`가 라인별로 매칭해 현재 값을 추출하고 `VersionFileWriter`가 같은 캡처 위치를 대체합니다. `VersionSourceRule`이 doctor 단계에서 파일 존재와 패턴 매칭을 동시에 점검하므로, 패턴 오타는 release 실행 전에 잡힙니다.

`relios init`이 생성하는 정형 `AppVersion.swift`는 `static let current = "0.1.0"`, `static let build = "1"` 형태이며, 기본 패턴 `'static let current = "(.*)"'`, `'static let build = "(.*)"'`와 짝을 이룹니다.

### 5.4 [build]

빌드 명령과 산출물 경로를 정의합니다. `command`는 raw shell command로 실행되므로 모든 옵션(configuration, scheme, derivedDataPath)을 이 문자열에 포함시켜야 합니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `command` | `command` | string | — | 필수 | `SwiftBuildRunner`가 `runShell`로 실행 |
| `binaryPath` | `binary_path` | string | — | 필수 (passthrough에서는 빈 값 허용) | assembly 단계에서 `.app/Contents/MacOS/`로 복사할 원본 바이너리 |
| `resourceBundlePath` | `resource_bundle_path` | string? | `nil` (빈 문자열도 `nil` 처리) | 선택 | `AppBundleAssembler`가 `.app/Contents/Resources/`로 복사할 SwiftPM resource bundle |

`command`는 그대로 `/bin/sh -c`로 넘어가므로, 따옴표·환경 변수 확장·`&&` 같은 셸 문법을 그대로 쓸 수 있습니다. 빌드는 `project.root` 디렉터리를 cwd로 실행됩니다.

`binary_path`는 assembly 모드에서만 의미가 있습니다. 파일명(`lastPathComponent`)은 `.app/Contents/MacOS/<binaryName>`의 최종 파일명으로 그대로 쓰입니다. passthrough 모드에서는 `xcodebuild`가 이미 완성된 `.app`을 만들기 때문에 빈 문자열로 둘 수 있습니다. SwiftBuildRunner는 이 경로가 빌드 후 존재하는지 검증하며, 누락 시 사용자에게 명확히 알립니다.

`resource_bundle_path`는 디코딩 시 빈 문자열(`""`)이 자동으로 `nil`로 변환됩니다. 값이 있으면 SwiftPM resource bundle(보통 `MyApp_MyApp.bundle`) 전체를 `Resources/`로 복사합니다. 미지정 시 리소스 복사 단계가 건너뜁니다.

### 5.5 [assets]

번들에 포함될 아이콘 경로를 정의합니다. 현재는 단일 필드만 존재합니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `iconPath` | `icon_path` | string? | `nil` (빈 문자열도 `nil` 처리) | 선택 | `.app/Contents/Resources/<iconName>` 복사, Info.plist의 `CFBundleIconFile` |

빈 문자열은 디코딩 단계에서 `nil`로 정규화됩니다. 값이 있으면 `AppBundleAssembler`가 파일을 그대로 `Resources/`에 복사하고, 그 파일명(`lastPathComponent`)을 Info.plist의 `CFBundleIconFile`로 기록합니다. `.icns` 확장자가 권장되지만 Relios는 검증하지 않습니다. 미지정 시 아이콘 없이 번들이 생성되며, macOS는 기본 앱 아이콘으로 대체 표시합니다.

passthrough 모드에서는 이 필드가 무시됩니다(`.app`이 이미 완성된 상태이므로 Relios가 리소스를 건드리지 않음).

### 5.6 [bundle]

`.app` 생성 방식과 출력 위치를 정의하는 섹션. `mode`가 전체 파이프라인의 분기를 결정합니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `outputPath` | `output_path` | string | — | 필수 | assembly: Relios가 만들 `.app` 경로 / passthrough: xcodebuild가 만들어 둔 `.app` 경로 |
| `plistMode` | `plist_mode` | enum (`generate`) | — | 필수 | 현재 `generate`만 허용 |
| `mode` | `mode` | enum (`assembly` \| `passthrough`) | `assembly` | 선택 | 어셈블리/생략 분기 |

`mode`만 `decodeIfPresent ?? .assembly`로 기본값이 있고, 나머지는 필수입니다. 기본값이 `assembly`인 이유는 `mode` 필드가 없는 기존 `relios.toml`과의 하위 호환입니다.

- `mode = "assembly"`: Relios가 빈 디렉터리에서 `.app`을 새로 만들고(`AppBundleAssembler`), 바이너리·리소스·아이콘을 복사한 뒤 `InfoPlistWriter`로 Info.plist를 생성합니다. `output_path`는 보통 `dist/<name>.app`처럼 산출물 디렉터리를 가리킵니다.
- `mode = "passthrough"`: 이미 빌드된 `.app`(주로 `xcodebuild`의 결과)이 `output_path`에 있다고 가정하고, Relios는 어셈블리·Info.plist 생성을 모두 건너뛰고 바로 서명·백업·설치 단계로 진행합니다. `XcodeProjectGuardRule`은 Xcode 프로젝트 마커가 있는데 mode가 assembly로 설정되어 있으면 명시적으로 실패시켜 잘못된 조합을 차단합니다.

`plist_mode`는 현재 `generate` 한 값만 정의돼 있으며, passthrough 모드에서는 사실상 무시됩니다(Relios가 plist를 건드리지 않음). 미래 확장(예: 사용자 작성 plist 병합)을 위한 enum slot입니다.

### 5.7 [install]

빌드된 `.app`을 어디에 설치하고 어떻게 다룰지 정의합니다. 5개 필드 모두 필수이며 기본값이 없습니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `path` | `path` | string | — | 필수 | 설치 대상 절대 경로 (보통 `/Applications/<name>.app`) |
| `autoOpen` | `auto_open` | bool | — | 필수 | 설치 완료 후 `open`으로 실행 여부 |
| `backupDir` | `backup_dir` | string | — | 필수 | 기존 `.app`을 복사해 둘 디렉터리 |
| `keepBackups` | `keep_backups` | int | — | 필수 | 보존할 백업 개수 (초과분은 삭제) |
| `quitRunningApp` | `quit_running_app` | bool | — | 필수 | 설치 직전 같은 bundle_id 프로세스 종료 여부 |

`install.path`는 CLI 플래그 `--install-path`로 덮어쓸 수 있습니다(`options.installPath ?? spec.install.path`). `InstallPathRule`은 부모 디렉터리(`/Applications` 등)가 실재하는지 doctor 단계에서 확인합니다.

`quit_running_app = true`이면 설치 직전 `bundle_id`로 실행 중인 프로세스를 찾아 종료하고, 같은 옵션이 rollback에도 적용됩니다(`RollbackRunner`). `auto_open`은 `--no-open` CLI 플래그로 비활성화할 수 있습니다(`spec.install.autoOpen && !options.noOpen`).

`backup_dir`은 release 직전 기존 `.app`을 `<backupDir>/<timestamp>/<name>.app`으로 복사하고, `keep_backups`를 초과한 가장 오래된 폴더를 정리합니다. rollback은 같은 디렉터리에서 백업을 골라 복원합니다.

### 5.8 [signing]

코드 서명 방식과 자격 증명을 정의합니다. `mode`만 필수이고 나머지 필드는 모두 선택이며, 빈 문자열은 디코딩 단계에서 `nil`로 정규화됩니다(`nilIfEmpty`).

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `mode` | `mode` | enum (`adhoc` \| `keep` \| `developer-id`) | — | 필수 | 서명 단계의 분기 |
| `identity` | `identity` | string? | `nil` | 선택 (developer-id에서는 사실상 필수) | `codesign --sign` 인자 |
| `teamID` | `team_id` | string? | `nil` | 선택 | 노타라이제이션 자격 증명 검증에 사용 |
| `hardenedRuntime` | `hardened_runtime` | bool | `true` | 선택 | `codesign --options runtime` on/off |
| `entitlementsPath` | `entitlements_path` | string? | `nil` | 선택 | `codesign --entitlements` 인자 |

`mode` 의미:

| mode | 설명 | identity/team_id |
|---|---|---|
| `adhoc` | `codesign --sign -` 로 ad-hoc 서명. 로컬 실행만 가능, 배포 불가 | 무시됨 |
| `keep` | 기존 서명을 그대로 둠. 주로 xcodebuild가 이미 서명한 passthrough 모드용 | 무시됨 |
| `developer-id` | Apple Developer ID 서명. 키체인의 인증서 사용 | `identity` 필수, `team_id`도 사실상 필수 |

`identity`는 `developer-id` 모드일 때만 의미가 있습니다. 파이프라인이 직접 검사해서 `nil`이면 실패합니다(`spec.signing.identity` 옵셔널 언래핑). 형식은 keychain의 정식 인증서 이름(예: `"Developer ID Application: Chan (ABCDE12345)"`)을 그대로 사용합니다.

`team_id`는 `identity` 끝의 괄호에서 파싱한 10자 팀 ID입니다. `signing setup`이 자동으로 채워주며, `NotarizeReadinessRule`과 `NotarizeCommand`가 환경변수의 `APPLE_TEAM_ID`와 교차 검증할 때 읽습니다(불일치하면 도움말과 함께 실패).

`hardened_runtime`은 `decodeIfPresent ?? true`로 기본 활성화됩니다. Developer ID 바이너리는 노타라이제이션을 통과하려면 hardened runtime이 필요하기 때문이며, 끄는 것은 로컬 실험용입니다. `entitlements_path`는 값이 있으면 `codesign --entitlements <path>`를 추가합니다.

`NotarizeReadinessRule`은 `[notarize].enabled = true`인데 `signing.mode != .developerID`이면 명시적으로 실패시켜 잘못된 조합을 사전에 차단합니다.

### 5.9 [dmg] (선택)

DMG 패키징 설정입니다. 섹션이 통째로 없으면 `spec.dmg`는 `nil`이고 DMG 생성·노타라이제이션 타깃 후보에서 모두 제외됩니다. 섹션은 있는데 `enabled = false`인 경우도 동일하게 건너뜁니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `enabled` | `enabled` | bool | `true` | 선택 | false면 DMG 단계 건너뜀 |
| `outputDir` | `output_dir` | string | `"dist"` | 선택 | DMG 산출물 디렉터리 |
| `volumeName` | `volume_name` | string? | `nil` (빈 문자열 포함) | 선택 | DMG 마운트 시 표시될 볼륨명. `nil`이면 `app.name`을 사용 |
| `backgroundColor` | `background_color` | string | `"#FCF5F3"` | 선택 | `dmgbuild` settings의 `background_color` |
| `windowWidth`/`windowHeight` | `window_size` | int 배열 `[w, h]` | `[540, 360]` | 선택 | Finder 창 크기 |
| `iconSize` | `icon_size` | int | `80` | 선택 | DMG 안 아이콘 픽셀 크기 |

`window_size`는 2원소 정수 배열이어야 하며, 길이가 2가 아니면 `DecodingError.dataCorruptedError`로 실패합니다(`"window_size must be a 2-element array [width, height]"`). 디코더는 이 배열을 `windowWidth`/`windowHeight`로 분해해 저장합니다.

`volume_name`이 비어 있으면 `DMGBuilder`가 `app.name`을 자동으로 채워 사용합니다(`dmg.volumeName ?? baseName`). 배경 이미지·볼륨 아이콘은 의도적으로 노출되지 않습니다(가이드의 "숨겨야 할 파일을 만들지 마라" 원칙).

이 섹션이 없으면:

- `relios release`는 DMG 생성 단계를 건너뜁니다.
- `relios dmg` 명령은 실행 자체가 거부됩니다(설정 없음).
- `[notarize].target = "auto"`는 zip으로 폴백합니다(`NotarizeTargetResolver`).

### 5.10 [notarize] (선택)

Apple 노타라이제이션 설정입니다. 자격 증명(`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`)은 TOML이 아니라 환경변수에서만 읽습니다 — `relios.toml`을 commit-safe하게 유지하기 위함입니다.

| 필드 | TOML 키 | 타입 | 기본값 | 필수 | 사용처 |
|---|---|---|---|---|---|
| `enabled` | `enabled` | bool | `true` | 선택 | false면 노타라이제이션 단계 건너뜀 |
| `target` | `target` | enum (`auto` \| `dmg` \| `zip`) | `auto` | 선택 | 어떤 산출물을 제출할지 |
| `timeoutSeconds` | `timeout_seconds` | int | `3600` (60분) | 선택 | `xcrun notarytool submit --wait`의 최대 대기 시간 |

`target = "auto"`는 `NotarizeTargetResolver`가 `[dmg].enabled == true`이면 DMG를, 아니면 zip(`<name>-<tag>.zip`)을 선택합니다. `dmg`로 명시했는데 `[dmg]` 섹션이 없거나 비활성이면 에러로 실패합니다.

`timeout_seconds`는 60분이 기본값입니다. Apple은 5–15분이라 안내하지만 2025년 관측치는 20–45분이 흔하고 한 시간을 넘기는 경우도 있어 여유를 둔 값입니다.

이 섹션이 없거나 `enabled = false`이면:

- `relios release`는 노타라이제이션·스테이플 단계를 건너뜁니다.
- `relios notarize` 명령은 실행 자체가 거부됩니다.
- `NotarizeReadinessRule`은 doctor 단계에서 아무 검사도 하지 않습니다.

활성 시 `NotarizeReadinessRule`이 다음을 강제합니다:

1. `[signing].mode == "developer-id"`여야 함 (아니면 명시적 실패와 함께 가이드 메시지)
2. 환경변수 자격 증명 존재 (별도 검증)
3. `[signing].team_id`와 환경변수 `APPLE_TEAM_ID` 불일치 시 경고/실패

### 5.11 전체 예시

#### SwiftPM (assembly) — 최소 구성

```toml
[app]
name = "MyApp"
display_name = "My App"
bundle_id = "com.example.myapp"
min_macos = "14.0"
category = "public.app-category.developer-tools"

[project]
type = "swiftpm"
root = "."
binary_target = "MyApp"

[version]
source_file = "AppVersion.swift"
version_pattern = 'static let current = "(.*)"'
build_pattern = 'static let build = "(.*)"'

[build]
command = "swift build -c release"
binary_path = ".build/release/MyApp"
resource_bundle_path = ""

[assets]
icon_path = ""

[bundle]
output_path = "dist/MyApp.app"
plist_mode = "generate"
mode = "assembly"

[install]
path = "/Applications/MyApp.app"
auto_open = true
backup_dir = "dist/app-backups"
keep_backups = 3
quit_running_app = true

[signing]
mode = "adhoc"
```

#### Xcode (passthrough) — Developer ID + DMG + 노타라이제이션

```toml
[app]
name = "MyApp"
display_name = "My App"
bundle_id = "com.example.myapp"
min_macos = "14.0"
category = "public.app-category.developer-tools"

[project]
type = "xcodebuild"
root = "."
binary_target = "MyApp"

[version]
source_file = "AppVersion.swift"
version_pattern = 'static let current = "(.*)"'
build_pattern = 'static let build = "(.*)"'

[build]
command = "xcodebuild -scheme MyApp -configuration Release -derivedDataPath build build"
binary_path = ""
resource_bundle_path = ""

[assets]
icon_path = ""

[bundle]
output_path = "build/Build/Products/Release/MyApp.app"
plist_mode = "generate"
mode = "passthrough"

[install]
path = "/Applications/MyApp.app"
auto_open = true
backup_dir = "dist/app-backups"
keep_backups = 3
quit_running_app = true

[signing]
mode = "developer-id"
identity = "Developer ID Application: Chan (ABCDE12345)"
team_id = "ABCDE12345"
hardened_runtime = true
entitlements_path = ""

[dmg]
enabled = true
output_dir = "dist"
volume_name = "MyApp"
background_color = "#FCF5F3"
window_size = [540, 360]
icon_size = 80

[notarize]
enabled = true
target = "auto"
timeout_seconds = 3600
```

### 5.12 모드별 핵심 차이 요약

| 섹션·필드 | assembly | passthrough |
|---|---|---|
| `[project].type` | `swiftpm` | `xcodebuild` |
| `[build].command` | `swift build -c release` 등 | `xcodebuild ...` (scheme·configuration·derivedDataPath 포함) |
| `[build].binary_path` | 빌드 산출 바이너리 경로 (필수) | 빈 문자열 가능 |
| `[assets].icon_path` | Relios가 `.app`에 복사 | 무시됨 |
| `[bundle].mode` | `assembly` | `passthrough` |
| `[bundle].output_path` | Relios가 만들 `.app` (예: `dist/MyApp.app`) | xcodebuild가 만들어 둔 `.app` (예: `build/Build/Products/Release/MyApp.app`) |
| `[bundle].plist_mode` | `generate` (실제로 plist 생성) | `generate`이지만 사용되지 않음 |
| `[signing].mode` | 보통 `adhoc` 또는 `developer-id` | 보통 `keep` 또는 `developer-id` |

| 시나리오 | `[dmg]` | `[notarize]` | 결과 |
|---|---|---|---|
| 로컬 개발 | 생략 | 생략 | 빌드·서명·설치만 |
| 사내 배포(서명만) | `enabled = true` | 생략 | DMG 생성 후 종료 |
| 외부 배포 | `enabled = true` | `enabled = true` | DMG 또는 zip을 노타라이즈+스테이플 |
| zip-only 노타라이즈 | 생략 | `target = "zip"` | release 산출 zip만 노타라이즈 |
