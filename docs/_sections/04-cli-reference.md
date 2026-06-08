## 4. CLI 명령어 레퍼런스

이 섹션은 Relios가 노출하는 모든 서브커맨드와 플래그를 소스 코드 기준으로 정확히 정리합니다. 개념적 배경(assembly/passthrough, 서명 모드, dry-run 의미 등)은 Section 3에서 정의되었으므로 여기서는 "이 명령을 어떻게 호출하고, 무엇이 일어나며, 왜 실패하는가"만 다룹니다. TOML 필드의 의미와 기본값은 Section 5에서, 여러 명령을 엮은 실전 워크플로우는 Section 7에서 다룹니다.

전체 명령은 `ReliosCommand`의 서브커맨드로 등록되어 있으며(`Sources/ReliosCLI/ReliosCommand.swift`), 모두 `relios <subcommand> [options]` 형태로 호출합니다. 성공 시 종료 코드는 `0`, 실패 시 ArgumentParser의 `ExitCode.failure`(`1`)이 반환됩니다.

### 4.1 `relios init`

- **목적**: 프로젝트 루트를 스캔해 `relios.toml` 스켈레톤과 `AppVersion.swift`를 생성합니다.
- **사용법**: `relios init`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| (플래그 없음) | — | — | `init`은 인자/플래그를 받지 않습니다. |

#### 내부 동작 요약

`InitCommand.run()`은 현재 디렉터리(`FileManager.default.currentDirectoryPath`)에서 다음 순서를 실행합니다.

1. `ProjectScanner.scan(root:)` — `Package.swift`가 있으면 `.swiftpm`, `.xcodeproj`/`.xcworkspace`/`project.yml` 마커가 있으면 `.xcodebuild`로 판별. SwiftPM의 경우 `Sources/<Name>/<Name>.swift` 패턴을 찾아 `binary_target`을 자동 결정합니다(없으면 단일 타겟 디렉터리, 그것도 모호하면 프로젝트 루트 basename).
2. `SpecSkeleton.from(scan:)` — 스캔 결과로 TOML 스켈레톤을 만듭니다. Xcode 프로젝트면 `bundle.mode`가 `passthrough`로, SwiftPM이면 `assembly`(기본)로 설정됩니다.
3. `KeychainIdentityLister.list()` — `security find-identity -v -p codesigning`을 실행해 "Developer ID Application" 인증서를 탐색합니다. **정확히 한 개**가 발견되고 식별자 끝의 10자 Team ID를 파싱할 수 있으면 `[signing].mode = "developer-id"`로 자동 채워집니다. 0개·복수·파싱 실패는 `adhoc` 그대로 두고 요약에 그 이유를 출력합니다.
4. `SpecSkeletonWriter.write(_:to:)` — `relios.toml`을 작성합니다.
5. `AppVersion.swift`가 없으면 `writeVersionSource(_:to:)`로 `0.1.0` (build `1`) 시드를 생성합니다. **이미 존재하면 덮어쓰지 않습니다.**

#### 예시

```bash
$ cd ~/Projects/MyApp
$ relios init
✓ Initialized Relios

Created files:
  relios.toml
  AppVersion.swift

Detected:
  project type:  swiftpm
  binary target: MyApp
  signing:       developer-id (ABCDE12345)
                 Developer ID Application: Chan (ABCDE12345)

Review before first release:
  [app].bundle_id      (currently com.example.MyApp)
  AppVersion.swift     (generated with 0.1.0 build 1)
  [assets].icon_path   (currently empty)

Next step:
  relios doctor
```

#### 실패 시나리오

- **`[init] failed — Reason: Not a SwiftPM project`**: 현재 디렉터리에 `Package.swift`도 Xcode 마커도 없습니다. 프로젝트 루트에서 실행했는지 확인하세요.
- **키체인 조회 실패**: `signing: adhoc (could not query keychain)`로 표시되지만 `init` 자체는 성공합니다. 이후 `relios signing setup`으로 수동 설정하면 됩니다.

### 4.2 `relios doctor`

- **목적**: 현재 프로젝트가 릴리스 가능한 상태인지 8개 규칙으로 진단합니다(규칙 정의는 Section 8 참조).
- **사용법**: `relios doctor [-v|--verbose]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `-v`, `--verbose` | flag | `false` | 진단 출력에 추가 정보를 더합니다. |
| `--fix` | flag (hidden) | `false` | 안전한 자동 수정을 적용합니다. 첫 자동수정 규칙이 구현되기 전까지 `--help`에서 숨김 상태로 유지됩니다. |

#### 내부 동작 요약

`DoctorRunner`가 다음 규칙을 이 순서대로 평가합니다(`DoctorCommand.swift`).

`XcodeProjectGuardRule`, `SpecValidityRule`, `VersionSourceRule`, `BuildReadinessRule`, `InstallPathRule`, `SigningReadinessRule`, `DMGReadinessRule`, `NotarizeReadinessRule`.

각 규칙은 `.ok` / `.warn` / `.fail` 중 하나를 반환합니다. 하나라도 `.fail`이면 종료 코드 `1`로 종료하며, 마지막 줄에 종합 상태(`ready` / `mostly ready` / `not ready`)를 출력합니다.

#### 예시

```bash
$ relios doctor
[ok]   Xcode project guard
[ok]   Spec validity
[ok]   Version source
[ok]   Build readiness
[warn] Install path
  Reason: /Applications is not writable without sudo
  Fix: Re-run with sudo, or change [install].path to ~/Applications
[ok]   Signing readiness
[ok]   DMG readiness
[ok]   Notarize readiness

Status: mostly ready
```

#### 실패 시나리오

- **`[fail] spec load`**: `relios.toml`이 없거나 파싱이 실패했습니다. `relios init`을 먼저 실행하거나 TOML 문법을 확인하세요.
- **`[fail] Signing readiness`**: `[signing].mode = "developer-id"`인데 키체인에 해당 인증서가 없습니다. `relios signing import` 또는 `relios signing setup`을 실행하세요.

### 4.3 `relios release`

- **목적**: preflight → 빌드 → 검증 → 버전 갱신 → 번들 조립 → 서명 → 백업 → 설치 → 실행 → manifest 작성을 한 번에 수행합니다.
- **사용법**: `relios release [patch|minor|major] [options]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `bump` (위치 인자) | `patch \| minor \| major` | (생략) | 버전을 어떻게 올릴지. 생략하면 빌드 번호만 +1, 지정하면 해당 자릿수를 올리고 빌드 번호는 1로 초기화됩니다. |
| `--dry-run` | flag | `false` | 빌드/검증까지만 수행하고 디스크에 아무것도 쓰지 않습니다(Gate 5 불변 조건). |
| `--no-open` | flag | `false` | 설치 후 앱을 자동 실행하지 않습니다. `[install].auto_open = true`라도 무시합니다. |
| `--install-path` | string | (TOML의 `[install].path`) | TOML 설정을 일회성으로 덮어씁니다. 예: `--install-path ~/Applications/MyApp.app`. |
| `--skip-backup` | flag | `false` | 기존 설치본의 백업 zip 생성을 건너뜁니다. |
| `-v`, `--verbose` | flag | `false` | 실패 시 stderr 마지막 200줄을 함께 출력합니다(빌드/서명 실패에 한정). |

#### 내부 동작 요약

`ReleasePipeline.run(spec:projectRoot:options:)`가 다음 14단계로 동작합니다(`Sources/ReliosCore/Release/ReleasePipeline.swift`).

1. **Preflight**: `XcodeProjectGuardRule`, `SpecValidityRule`, `VersionSourceRule`, `BuildReadinessRule`, `SigningReadinessRule` 평가. 하나라도 fail이면 `ReleaseError.preflightFailed`.
2. **현재 버전 읽기**: `VersionSourceReader`가 `[version].source_file`을 정규식으로 파싱.
3. **다음 버전 계산**: `bump`가 있으면 해당 자릿수 +1 후 빌드를 `.initial`(=1)로 리셋, 없으면 빌드만 +1.
4. **빌드 실행**: `SwiftBuildRunner.runBuild()`가 `[build].command`를 그대로 실행.
5. **산출물 검증**: assembly 모드면 `[build].binary_path` 후보를 탐색, passthrough 모드면 `[bundle].output_path`의 `.app` 디렉터리 존재만 확인.
6. **(dry-run이면 여기서 종료 — 디스크 쓰기 없음)**
7. **버전 소스 갱신**: `VersionSourceUpdater`가 정규식 치환으로 `AppVersion.swift`(또는 지정 파일)에 새 값을 씁니다.
8. **번들 조립** (assembly 모드만): `AppBundleAssembler`가 `Contents/MacOS/<binary>`, `Contents/Resources/`(아이콘 포함)를 구성.
9. **Info.plist 작성** (assembly 모드만): `InfoPlistWriter`.
10. **서명**: `[signing].mode`에 따라 `AdhocSigner` / `DeveloperIDSigner` / 아무 것도 안 함(`keep`).
11. **백업**: `--skip-backup`이 없고 기존 설치본이 있으면 `BackupManager`가 `[install].backup_dir`에 `<App>-<prevVer>-<prevBuild>.zip`을 생성. 이후 `[install].keep_backups` 초과분은 오래된 순으로 삭제.
12. **실행 중인 앱 종료**: `[install].quit_running_app`이면 `RunningAppTerminator`가 bundle ID 기반으로 종료.
13. **설치**: `AppInstaller`가 `[install].path`(또는 `--install-path`)로 .app 복사.
14. **자동 실행**: `[install].auto_open`이고 `--no-open`이 없으면 `AppLauncher`가 `open`으로 실행.
15. **manifest 작성**: `dist/releases/<timestamp>.json`과 `dist/releases/latest.json` 갱신.

#### 예시

```bash
# 일반 릴리스 (patch 올리고 자동 실행)
$ relios release patch
✓ Preflight passed
✓ Version: 0.1.0 (build 12) → 0.1.1 (build 1)
✓ Build completed
✓ Verified build artifact
✓ Updated version source
✓ Assembled .app bundle
✓ Generated Info.plist
✓ Signed (developer-id)
✓ Backed up previous app
✓ Installed to /Applications/MyApp.app
✓ Launched MyApp

  Bundle:  /path/to/MyApp/dist/MyApp.app
  Install: /Applications/MyApp.app
  Backup:  /path/to/MyApp/dist/backups/MyApp-0.1.0-12.zip

# 안전 점검용 dry-run
$ relios release minor --dry-run
✓ Preflight passed
✓ Version: 0.1.1 (build 1) → 0.2.0 (build 1)
✓ Build completed
✓ Verified build artifact

Dry run — no files were written.
```

#### 실패 시나리오

- **`[release] failed at: preflight validation`**: doctor가 잡지 못한 항목이 release 직전에 다시 검증됩니다. `relios doctor`로 원인을 좁히세요.
- **`[release] failed at: build`**: `[build].command`가 0이 아닌 코드로 종료됨. `-v`로 stderr 마지막 줄을 확인하세요.
- **`[release] failed at: verify build artifact`**: 빌드는 성공했지만 `[build].binary_path`가 잘못됨. 오류 메시지에 "Searched: ..." 후보 경로가 출력되니 TOML을 수정합니다.
- **`[release] failed at: install`**: 대상이 시스템 디렉터리(`/Applications`)면 권한 부족일 수 있습니다. `sudo relios release`로 재시도하거나 `--install-path ~/Applications/...`로 우회.

### 4.4 `relios build`

- **목적**: `[build].command`만 실행하고 설치/서명/번들링은 건너뛰는 빌드 단독 명령.
- **사용법**: `relios build [-v|--verbose]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `-v`, `--verbose` | flag | `false` | 빌드 출력 verbose. |

#### 내부 동작 요약

현재 구현은 스텁(`print("[build] not implemented yet")`)입니다. 빌드만 단독 실행하려면 임시로 `--dry-run` 옵션의 `relios release`를 사용하거나 `[build].command`를 직접 실행하세요. 구현되면 `SwiftBuildRunner.runBuild()`를 단독으로 호출하는 형태가 될 예정입니다.

#### 실패 시나리오

- 현재 항상 안내 메시지를 출력하고 종료 코드 `0`으로 종료합니다(에러 아님).

### 4.5 `relios install`

- **목적**: 가장 최근에 빌드된 `.app`을 재빌드 없이 `[install].path`로 복사합니다.
- **사용법**: `relios install [--no-open] [--skip-backup] [-v|--verbose]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `--no-open` | flag | `false` | 설치 후 자동 실행하지 않음. |
| `--skip-backup` | flag | `false` | 기존 설치본 백업 생략. |
| `-v`, `--verbose` | flag | `false` | verbose 출력. |

#### 내부 동작 요약

현재 구현은 스텁입니다. 구현되면 `[bundle].output_path`의 `.app`을 입력으로 `BackupManager` → `RunningAppTerminator` → `AppInstaller` → `AppLauncher` 순서로 동작할 예정이며, 이는 `ReleasePipeline`의 11~14단계와 동일한 구성요소입니다.

#### 실패 시나리오

- 현재 항상 `[install] not implemented yet`을 출력하고 종료 코드 `0`으로 종료합니다.

### 4.6 `relios inspect`

- **목적**: 최신 릴리스 manifest(`dist/releases/latest.json`)와 현재 설치된 앱의 상태를 한눈에 보여줍니다.
- **사용법**: `relios inspect`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| (플래그 없음) | — | — | `inspect`는 인자/플래그를 받지 않습니다. |

#### 내부 동작 요약

`InspectReader.readLatest(releasesDir:)`가 `dist/releases/latest.json`을 디코딩해 `ReleaseManifest` 구조체로 변환합니다. manifest는 `relios release` 14단계 마지막에 작성되며 앱 이름, bundle ID, 버전, 빌드, 번들 경로, 설치 경로, 백업 경로, bundle/signing 모드, 자동 실행 여부, ISO8601 타임스탬프를 포함합니다.

#### 예시

```bash
$ relios inspect
Latest Release

  App:       MyApp
  Bundle ID: com.example.MyApp
  Version:   0.2.0 (build 1)
  Bundle:    /path/to/MyApp/dist/MyApp.app
  Install:   /Applications/MyApp.app
  Backup:    /path/to/MyApp/dist/backups/MyApp-0.1.1-3.zip
  Mode:      assembly
  Signing:   developer-id
  Launched:  yes
  Timestamp: 2026-05-25T10:42:11Z
```

#### 실패 시나리오

- **`[inspect] No release manifest found. Run \`relios release\` first.`**: `dist/releases/latest.json`이 없습니다. 한 번도 릴리스를 수행하지 않은 신규 프로젝트입니다.
- **`[inspect] Could not read release manifest: ...`**: JSON 디코딩이 실패했습니다. manifest를 수동 편집했다면 백업본으로 복구하거나 다음 릴리스를 한 번 더 실행하세요.

### 4.7 `relios rollback`

- **목적**: 가장 최근(또는 지정된) 백업 zip을 풀어 이전 버전의 앱을 설치 경로에 복원합니다.
- **사용법**: `relios rollback [--to <path>] [--no-open] [-v|--verbose]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `--to` | string | (최신 백업) | 복원할 백업 zip의 경로. 생략하면 `[install].backup_dir`에서 알파벳 정렬상 가장 마지막 zip을 선택. |
| `--no-open` | flag | `false` | 복원 후 자동 실행하지 않음. |
| `-v`, `--verbose` | flag | `false` | verbose 출력. |

#### 내부 동작 요약

`RollbackRunner.run(...)` 흐름(`Sources/ReliosCore/Rollback/RollbackRunner.swift`).

1. **백업 결정**: `--to`가 있으면 그 경로를 사용, 없으면 `[install].backup_dir`을 listing 후 `.zip` 파일을 정렬해 마지막을 선택.
2. **실행 중 앱 종료**: `[install].quit_running_app`이면 `RunningAppTerminator`.
3. **기존 설치본 삭제**: `[install].path`가 존재하면 제거.
4. **압축 해제**: `/usr/bin/ditto -x -k <backup.zip> <install_path의 부모 디렉터리>`. ditto의 종료 코드 0을 신뢰합니다(별도 fileExists 검증은 mock 테스트와 충돌하기 때문에 의도적으로 생략).
5. **자동 실행**: `[install].auto_open`이고 `--no-open`이 없으면 `AppLauncher`.

#### 예시

```bash
# 최신 백업으로 자동 복원
$ relios rollback
✓ Restored from: /path/to/MyApp/dist/backups/MyApp-0.1.0-12.zip
✓ Installed at:  /Applications/MyApp.app
✓ Launched app

# 특정 백업 지정
$ relios rollback --to dist/backups/MyApp-0.1.0-10.zip --no-open
✓ Restored from: dist/backups/MyApp-0.1.0-10.zip
✓ Installed at:  /Applications/MyApp.app
```

#### 실패 시나리오

- **`No backup zips found in <dir>`**: 한 번도 백업이 생성되지 않았거나 `keep_backups`가 0이거나, `--skip-backup`만 써서 릴리스한 경우. 해결: 백업이 켜진 채로 한 번 릴리스를 돌립니다.
- **`Backup file not found: <path>`**: `--to`로 지정한 파일이 없습니다.
- **`Could not extract backup: ditto exited with code N`**: zip 무결성 손상. 다른 백업을 선택해 재시도하세요.

### 4.8 `relios open`

- **목적**: 현재 설치된 앱을 실행합니다.
- **사용법**: `relios open`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| (플래그 없음) | — | — | `open`은 인자/플래그를 받지 않습니다. |

#### 내부 동작 요약

현재 구현은 스텁입니다. 구현되면 `[install].path`에 대해 `AppLauncher.launch(appPath:)`(내부적으로 `/usr/bin/open`)를 호출하는 단일 단계 명령이 됩니다.

#### 실패 시나리오

- 현재 항상 `[open] not implemented yet`을 출력하고 종료 코드 `0`으로 종료합니다.

### 4.9 `relios ci`

GitHub Actions 워크플로우를 스캐폴드하고 점검하는 명령 그룹입니다. 기본 서브커맨드는 `init`(즉 `relios ci`만 실행해도 `relios ci init`과 동일).

#### 4.9.1 `relios ci init`

- **목적**: `relios.toml`을 읽고 `.github/workflows/release.yml`(태그 트리거 릴리스 파이프라인)과 `.github/workflows/ci.yml`(PR/push 빌드·테스트 게이트)을 생성합니다.
- **사용법**: `relios ci init [--force]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `--force` | flag | `false` | 두 파일 중 하나라도 이미 존재하면 덮어씁니다. 없으면 충돌 파일을 모두 묶어서 한 번에 보고하고 종료. |

##### 내부 동작 요약

`CIInitRunner.run(projectRoot:force:)`(`Sources/ReliosCore/CI/CIInitRunner.swift`).

1. `relios.toml` 존재 확인 → 없으면 `CIError.specMissing`.
2. `SpecLoader.load(from:)`로 스펙 로딩.
3. `.github/workflows/release.yml`, `.github/workflows/ci.yml`의 존재를 검사. `--force`가 아니고 둘 중 하나라도 있으면 `CIError.workflowExists`로 충돌 목록을 한 번에 반환(두 번 실행하게 만들지 않기 위해).
4. `Tests/` 디렉터리 존재 여부 탐지 → CI 워크플로우에서 `swift test` 단계 포함 여부 결정.
5. `ReleaseWorkflowRenderer().render(spec)` + `CIWorkflowRenderer().render(spec, hasTests:)`로 YAML 생성. `[dmg]`·`[notarize]`·`[signing].mode = developer-id`가 켜져 있으면 해당 단계가 자동 주입됩니다.

##### 예시

```bash
$ relios ci init
✓ Created .github/workflows/release.yml
✓ Created .github/workflows/ci.yml

Project type: swiftpm
Bundle mode:  assembly

Next steps:
  1. Commit the workflows:
       git add .github/workflows && git commit
  2. Push to trigger CI, or a tag to trigger a release:
       git tag v0.1.0 && git push origin v0.1.0
```

##### 실패 시나리오

- **`Workflows already exist: ...`**: `--force`로 덮어쓰거나 기존 파일을 삭제하세요. 두 파일을 한 번에 보고하므로 두 번 실행할 필요는 없습니다.
- **`relios.toml not found at <path>`**: 먼저 `relios init`을 실행하세요.

#### 4.9.2 `relios ci doctor`

- **목적**: GitHub Actions 릴리스에 필요한 환경(워크플로우 파일 존재, GitHub 리모트 등)이 갖춰졌는지 진단합니다.
- **사용법**: `relios ci doctor`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| (플래그 없음) | — | — | `ci doctor`는 인자/플래그를 받지 않습니다. |

##### 내부 동작 요약

`DoctorRunner`에 CI 전용 3개 규칙을 주입해서 실행합니다.

- `ReleaseWorkflowPresenceRule` — `.github/workflows/release.yml` 존재.
- `CIWorkflowPresenceRule` — `.github/workflows/ci.yml` 존재.
- `GitHubRemoteRule` — `git remote -v`에 GitHub 호스트가 등록되어 있는지 확인.

출력 포맷과 종료 코드 규칙은 `relios doctor`와 동일합니다(`fail`이 하나라도 있으면 종료 코드 `1`).

##### 예시

```bash
$ relios ci doctor
[ok]   Release workflow present
[ok]   CI workflow present
[ok]   GitHub remote configured

Status: ready
```

##### 실패 시나리오

- **`[fail] Release workflow present`**: `relios ci init`을 실행하세요.
- **`[fail] GitHub remote configured`**: `git remote add origin git@github.com:owner/repo.git`로 리모트를 추가하세요.

### 4.10 `relios signing`

키체인 식별자 점검, TOML `[signing]` 섹션 패치, .p12 인증서 임포트, 서명 검증을 다루는 명령 그룹입니다.

#### 4.10.1 `relios signing status`

- **목적**: 현재 키체인의 codesigning 식별자 목록과 `relios.toml [signing]` 섹션의 현재 값을 함께 표시합니다.
- **사용법**: `relios signing status`

##### 내부 동작 요약

`KeychainIdentityLister.list()`로 `security find-identity -v -p codesigning`을 실행하고, `SpecLoader`로 TOML을 읽어 둘을 나란히 출력합니다. `[signing].mode = "developer-id"`인데 TOML에 적힌 식별자가 키체인에 없으면 끝에 경고를 표시합니다.

##### 예시

```bash
$ relios signing status
Keychain identities (codesigning):
  • Developer ID Application: Chan (ABCDE12345) team=ABCDE12345
  • Apple Development: chan@example.com (XYZ987) team=XYZ9876543

relios.toml [signing]:
  mode             = developer-id
  identity         = Developer ID Application: Chan (ABCDE12345)
  team_id          = ABCDE12345
  hardened_runtime = true
  entitlements     = (none)
```

##### 실패 시나리오

- **`Could not query keychain: ...`**: `security` 호출 자체가 실패. macOS 환경 또는 권한 문제입니다.
- **TOML이 없을 때**: 에러가 아니라 `relios.toml not found (run \`relios init\` first).`만 출력합니다.

#### 4.10.2 `relios signing setup`

- **목적**: `[signing]` 섹션을 `developer-id` 모드로 채워 넣습니다(필요 시 대화형으로 식별자 선택).
- **사용법**: `relios signing setup [--identity <str>] [--team-id <str>] [--hardened-runtime] [--entitlements <path>] [--non-interactive]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `--identity` | string | (대화형 선택) | `Developer ID Application: Name (TEAM123456)` 형식의 코드 서명 식별자 이름. |
| `--team-id` | string | (식별자에서 파싱) | 10자 Apple Team ID. `--identity`에 포함된 값과 충돌하면 에러. |
| `--hardened-runtime` | flag | `true` | hardened runtime을 활성화. `[signing].hardened_runtime`에 기록됩니다. |
| `--entitlements` | string | (없음) | entitlements plist 경로. |
| `--non-interactive` | flag | `false` | 필수값이 부족할 때 prompt 없이 종료 코드 `1`로 실패. CI에서 사용. |

##### 내부 동작 요약

`SetupSubcommand.run()` 흐름.

1. `relios.toml`이 없으면 즉시 종료(`Run \`relios init\` first.`).
2. `KeychainIdentityLister.list()`로 키체인 식별자 조회(실패해도 빈 배열로 계속).
3. `--identity`가 주어졌으면 그대로 사용하고 `--team-id`가 따로 주어졌으면 식별자에서 파싱한 Team ID와 일치 검증. 미일치면 종료.
4. `--identity` 미지정 + `--non-interactive` → 에러로 종료.
5. 인터랙티브 모드: "Developer ID Application" 후보 추출. 1개면 그대로 사용, 여러 개면 번호 입력 prompt.
6. Team ID가 식별자에서 파싱되지 않고 `--team-id`도 없으면 prompt(`--non-interactive`면 에러).
7. `SigningSectionPatcher().patch(...)`로 기존 TOML을 정규식 기반으로 패치하여 작성. 다른 섹션은 건드리지 않습니다.

##### 예시

```bash
# CI/스크립트용 — 모든 값을 플래그로 전달
$ relios signing setup \
    --identity "Developer ID Application: Chan (ABCDE12345)" \
    --team-id ABCDE12345 \
    --non-interactive
✓ Updated /path/to/MyApp/relios.toml
  mode     = developer-id
  identity = Developer ID Application: Chan (ABCDE12345)
  team_id  = ABCDE12345

# 인터랙티브 — 키체인에 후보가 여러 개일 때
$ relios signing setup
Choose an identity:
  [1] Developer ID Application: Chan (ABCDE12345)
  [2] Developer ID Application: Acme Inc. (FGHIJ67890)
Enter number: 1
✓ Updated /path/to/MyApp/relios.toml
  ...
```

##### 실패 시나리오

- **`--team-id (X) does not match team in identity (Y)`**: 두 값이 어긋났습니다. 둘 중 하나만 전달하세요.
- **`No "Developer ID Application" identity in the keychain.`**: `relios signing import <path.p12>`를 먼저 실행하거나 Xcode → Settings → Accounts에서 인증서를 설치하세요.
- **`identity is not in the keychain yet.`**: 경고 형태로만 출력되며 TOML 패치는 그대로 진행됩니다. 이후 `relios signing import`로 추가하세요.

#### 4.10.3 `relios signing import`

- **목적**: `.p12` 인증서를 macOS 키체인에 임포트합니다(`-T /usr/bin/codesign`으로 codesign 접근 권한도 부여).
- **사용법**: `relios signing import <p12_path> [--keychain <name>] [--password-env <var>]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `p12Path` (위치 인자, 필수) | string | — | `.p12` 파일의 경로. 존재하지 않으면 에러. |
| `--keychain` | string | `login.keychain-db` | 임포트 대상 키체인 이름. CI에서는 임시 키체인을 생성해 격리하는 패턴이 권장됩니다. |
| `--password-env` | string | `RELIOS_CERT_PASSWORD` | `.p12`의 패스워드를 담은 환경변수 이름. 비어 있거나 미설정이면 에러. |

##### 내부 동작 요약

`ImportSubcommand.run()`은 다음 단일 명령으로 임포트를 수행합니다.

```bash
security import '<p12_path>' -k <keychain> -P '<password>' -T /usr/bin/codesign
```

종료 코드가 0이 아니면 stderr를 그대로 출력하고 실패. 성공하면 다음 단계로 `relios signing status` → `relios signing setup`을 안내합니다.

##### 예시

```bash
$ export RELIOS_CERT_PASSWORD='my-p12-password'
$ relios signing import ~/certs/developer-id.p12
✓ Imported /Users/chan/certs/developer-id.p12 into login.keychain-db
Next: run `relios signing status` to verify, then `relios signing setup`.
```

##### 실패 시나리오

- **`Error: env var RELIOS_CERT_PASSWORD is empty or unset.`**: 패스워드 환경변수를 먼저 export하세요(또는 `--password-env`로 다른 변수명을 지정).
- **`security import failed (exit 1) ... MAC verification failed`**: `.p12` 파일의 패스워드가 틀렸습니다.
- **`File not found: <path>`**: 경로 오타를 확인하세요.

#### 4.10.4 `relios signing verify`

- **목적**: `codesign --verify`와 `codesign -dv`를 실행해 .app의 서명 유효성과 상세 정보를 출력합니다.
- **사용법**: `relios signing verify [<app_path>]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `appPath` (위치 인자) | string | (`[bundle].output_path`) | 검증할 `.app` 경로. 생략하면 TOML의 `[bundle].output_path`를 프로젝트 루트 기준으로 해석. |

##### 내부 동작 요약

다음 두 명령을 순차 실행해 그대로 출력합니다.

```bash
codesign --verify --deep --strict --verbose=2 '<app_path>'
codesign -dv --verbose=4 '<app_path>'
```

첫 명령의 종료 코드가 0이 아니면 종료 코드 `1`로 실패. 두 번째 명령(`-dv`)은 정보 표시용이라 실패해도 종료 코드에 영향을 주지 않습니다.

##### 예시

```bash
$ relios signing verify dist/MyApp.app
--- codesign --verify ---
dist/MyApp.app: valid on disk
dist/MyApp.app: satisfies its Designated Requirement
--- codesign -dv ---
Executable=/path/to/dist/MyApp.app/Contents/MacOS/MyApp
Identifier=com.example.MyApp
Authority=Developer ID Application: Chan (ABCDE12345)
TeamIdentifier=ABCDE12345
Sealed Resources version=2 rules=13 files=42
```

##### 실패 시나리오

- **`<path>: code object is not signed at all`**: ad-hoc 서명도 안 되어 있는 상태. `relios release`를 다시 돌리거나 수동으로 `codesign --sign - <app>`을 실행.
- **`<path>: a sealed resource is missing or invalid`**: 서명 이후 번들 내부 파일이 변경되었습니다. 다시 빌드 후 재서명하세요.

### 4.11 `relios dmg`

- **목적**: 현재 `.app` 번들을 `dmgbuild`(Python 도구)로 DMG 패키지로 묶습니다.
- **사용법**: `relios dmg [-v|--verbose]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `-v`, `--verbose` | flag | `false` | dmgbuild의 서브프로세스 출력을 그대로 표시. |

#### 내부 동작 요약

`DMGBuilder.run(spec:projectRoot:version:)` 흐름(`Sources/ReliosCore/DMG/DMGBuilder.swift`).

1. `[dmg].enabled`가 `false`거나 섹션이 없으면 `DMGError.disabled`로 즉시 실패.
2. `[bundle].output_path`의 `.app` 존재 확인.
3. `[dmg].output_dir`(기본 `dist`) 디렉터리 보장. **기존 `*.dmg`는 모두 삭제** — 동일 버전을 여러 번 만들 때 stale 파일이 다음 단계를 혼란시키는 것을 막기 위함입니다.
4. 파일명 결정: 버전 정보가 있으면 `<AppName>-<x.y.z>.dmg`, 없으면 `<AppName>.dmg`. 볼륨명은 `[dmg].volume_name` 우선, 없으면 앱 basename.
5. `DMGSettingsRenderer().render(...)`로 `_dmg-settings.py`를 `output_dir`에 생성(성공·실패 모두 마지막에 삭제).
6. `command -v dmgbuild`로 PATH 확인 → 없으면 `DMGError.dmgbuildNotFound`.
7. `DMGBUILD_APP_PATH=<app> dmgbuild -s <settings.py> <volume> <out.dmg>` 실행. 종료 코드가 0이 아니면 stderr와 함께 에러 반환.

#### 예시

```bash
$ relios dmg
✓ Created dist/MyApp-0.2.0.dmg

$ relios dmg --verbose
... (dmgbuild의 stdout/stderr가 함께 표시됨) ...
✓ Created dist/MyApp-0.2.0.dmg
```

#### 실패 시나리오

- **`.app bundle not found at <path>`**: 먼저 `relios release`로 `.app`을 만드세요.
- **`` `dmgbuild` is not available on PATH ``**: `pipx install dmgbuild`(권장) 또는 `pip install dmgbuild`로 설치.
- **`dmgbuild exited with code N: ...`**: `--verbose`로 재실행해 dmgbuild의 전체 출력을 확인하세요. 자주 발생하는 원인은 `[dmg].settings_path`로 지정한 외부 설정 파일의 문법 오류입니다.

### 4.12 `relios notarize`

- **목적**: `.zip` 또는 `.dmg` 산출물을 Apple notarytool에 제출한 뒤 ticket을 staple까지 완료합니다.
- **사용법**: `relios notarize [<path>] [--timeout <seconds>]`

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `path` (위치 인자) | string | (자동 해석) | 노타라이즈할 `.zip`/`.dmg` 경로. 생략하면 `[notarize].target` 규칙에 따라 자동 해석. |
| `--timeout` | int (초) | `[notarize].timeout_seconds` (기본 `3600`) | `xcrun notarytool submit --wait`의 최대 대기 시간. |

위치 인자가 생략되었을 때의 해석 규칙(`NotarizeTargetResolver`):

- `[notarize].target = .dmg` → `[dmg].output_dir`에서 mtime 기준 가장 최근 `*.dmg`.
- `[notarize].target = .zip` → 프로젝트 루트의 `<AppName>-<version>.zip`(없으면 `<AppName>.zip`). 보통 CI가 만들어 두는 파일입니다.
- `[notarize].target = .auto`(기본) → `[dmg].enabled`이면 `.dmg`, 아니면 `.zip`.

#### 내부 동작 요약

`NotarizeCommand.run()` → `Notarizer.notarize(...)` 흐름(`Sources/ReliosCore/Notarize/Notarizer.swift`).

1. **스펙 로딩 + enable 확인**: `[notarize]` 섹션이 없거나 `enabled = false`면 `NotarizeError.disabled`.
2. **산출물 해석**: 위치 인자가 있으면 그 경로, 아니면 위 규칙으로 자동 선택. `.zip`/`.dmg`가 아니면 `NotarizeError.unsupportedArtifact`.
3. **자격증명**: `NotarizerCredentials.fromEnvironment(...)`가 `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`를 한 번에 검증. 비어 있는 변수는 모두 모아서 한 에러로 반환합니다(세 번 재실행하지 않도록).
4. **Team ID 일치 검증**: `[signing].team_id`와 `APPLE_TEAM_ID`가 다르면 제출 전에 즉시 실패(`NotarizeError.teamIDMismatch`).
5. **notarytool 존재 확인**: `xcrun notarytool --version`.
6. **제출**: `xcrun notarytool submit <artifact> --apple-id ... --password ... --team-id ... --wait --timeout <N>s`. 출력은 스트리밍으로 그대로 출력되어 CI 로그가 멈춰 보이지 않습니다. notarytool은 거부된 경우에도 exit 0을 반환하는 케이스가 있어 stdout을 `status: invalid|rejected` 키워드로 한 번 더 검사합니다.
7. **Staple**: `.dmg`이면 자체 staple → validate. `.zip`이면 ditto로 풀어 내부 `.app`을 staple/validate한 뒤 원본 위치에 다시 압축(zip 자체는 ticket을 담을 수 없기 때문).
8. **재시도**: `stapler staple`가 exit 65/66로 실패하면 Apple CDN의 ticket 전파 지연으로 보고 10초 간격으로 최대 3회 재시도.

#### 예시

```bash
$ export APPLE_ID='chan@example.com'
$ export APPLE_APP_SPECIFIC_PASSWORD='abcd-efgh-ijkl-mnop'
$ export APPLE_TEAM_ID='ABCDE12345'

# 자동 해석 (보통 가장 최근 DMG가 선택됨)
$ relios notarize
→ Submitting dist/MyApp-0.2.0.dmg to Apple notarization
  (may take 2-15 minutes depending on Apple queue load)
... (notarytool 출력 스트리밍) ...
✓ Notarized + stapled dist/MyApp-0.2.0.dmg

# 명시적 경로 + 짧은 타임아웃
$ relios notarize dist/MyApp-0.2.0.dmg --timeout 1800
...
```

#### 실패 시나리오

- **`Missing env vars: APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID`**: 세 변수를 모두 `export`하세요. App-Specific Password는 일반 Apple ID 패스워드가 아닌, [appleid.apple.com](https://appleid.apple.com) → Security에서 발급한 4-4-4-4 형식 값입니다.
- **`team_id mismatch: signing=ABCDE12345 vs APPLE_TEAM_ID=ZZZZZ99999`**: TOML의 `[signing].team_id`와 환경변수가 다른 팀입니다. 둘 중 하나를 수정하세요.
- **`` `xcrun notarytool` is not available ``**: 풀 Xcode 13+ 필요. Command Line Tools만으로는 사용할 수 없으며 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`로 전환이 필요할 수 있습니다.
- **`notarytool submit exited N: ... status: Invalid`**: Apple이 패키지를 거부함. 메시지에 포함된 submission ID로 `xcrun notarytool log <id> --apple-id ... --password ... --team-id ...`을 실행해 상세 거부 사유를 확인하세요.
- **`stapler staple exited 65`**: ticket이 아직 Apple CDN에 전파되지 않은 경우입니다. Relios가 자동 재시도(3회 × 10초)하지만 그래도 실패하면 1~2분 후 `relios notarize`를 다시 실행해도 동일 산출물에 대해 staple만 다시 시도됩니다(이미 노타라이즈된 산출물은 즉시 staple로 진행).
