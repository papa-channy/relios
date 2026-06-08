## 7. 엔드 투 엔드 워크플로우

이 섹션은 처음 Relios를 만지는 사람이 따라 칠 수 있도록 실제 사용 시나리오를 명령 단위로 풀어 둔다. 명령은 영어 그대로, 출력 예시는 실제 Relios가 찍는 텍스트를 모사한다. 각 명령의 모든 옵션은 Section 4, 각 TOML 필드의 기본값은 Section 5, doctor 규칙 내부 동작은 Section 8을 참고하라.

### 7.1 새 SwiftPM macOS 앱 스캐폴딩 → 첫 로컬 릴리스 (assembly 모드)

빈 디렉터리에서 시작해 `/Applications/MyApp.app`이 실행되는 상태까지 4개 명령으로 도달하는 흐름이다.

**1. 최소 SwiftPM 패키지 만들기**

```bash
mkdir myapp && cd myapp
```

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MyApp", path: "Sources/MyApp"),
    ]
)
```

`Sources/MyApp/App.swift`:

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { Text("Hello, Relios").padding(40) }
    }
}
```

이 시점에 디렉터리는 `Package.swift`, `Sources/MyApp/App.swift` 두 개뿐이다. `relios.toml`도, `AppVersion.swift`도 없다.

**2. `relios init` — 자동 감지와 파일 생성**

```bash
relios init
```

출력은 다음과 같은 모양이다.

```
✓ Initialized Relios

Created files:
  relios.toml
  AppVersion.swift

Detected:
  project type:  swiftpm
  binary target: MyApp
  signing:       adhoc (no Developer ID cert in keychain)

Review before first release:
  [app].bundle_id      (currently com.example.myapp)
  AppVersion.swift     (generated with 0.1.0 build 1)
  [assets].icon_path   (currently empty)

Next step:
  relios doctor
```

해석할 포인트.

- **project type: swiftpm** — `Package.swift`만 있고 `.xcodeproj`, `.xcworkspace`, `project.yml` 어느 것도 없어 assembly 모드가 선택됐다.
- **binary target: MyApp** — `Sources/MyApp/MyApp.swift`가 있으면 그 이름이 우선 채택되고, 없으면 `Sources/` 하위 단일 디렉터리 규칙으로 잡힌다. 이 예시는 단일 디렉터리 규칙으로 `MyApp`이 잡힌 경우.
- **signing: adhoc** — 키체인에 Developer ID Application 인증서가 없으므로 ad-hoc 서명이 채택됐다. 인증서가 있었다면 `signing: developer-id (TEAMID12)`로 자동 기입됐을 것이다 (7.3 참고).
- `bundle_id`는 `com.example.<lowercased-name>` 자리표시자. 첫 릴리스 전에 실제 역도메인으로 바꿔야 한다.

`relios.toml`은 다음 골격으로 작성된다 (필드 의미는 Section 5).

```toml
[app]
name = "MyApp"
bundle_id = "com.example.myapp"
...
[project]
type = "swiftpm"
binary_target = "MyApp"
[build]
command = "swift build -c release"
binary_path = ".build/release/MyApp"
[bundle]
output_path = "dist/MyApp.app"
mode = "assembly"
[install]
path = "/Applications/MyApp.app"
[signing]
mode = "adhoc"
```

**3. `relios doctor` — 6개 정적 규칙 통과 확인**

```bash
relios doctor
```

```
[ok] project type
[ok] spec validity
[ok] version source
[ok] build readiness
[ok] install path
[ok] signing readiness

Status: ready
```

하나라도 fail이 나오면 `release`는 시작되지 않는다. fail의 의미와 fix 안내는 Section 8.

**4. `relios release patch --dry-run` — 쓰기 없이 검증**

```bash
relios release patch --dry-run
```

dry-run은 "버전 소스 파일을 갱신하기 직전까지의 모든 검증을 끝낸다"가 정의다. 실패할 거면 이 시점에 실패한다.

```
✓ Preflight passed
✓ Version: 0.1.0 (build 1) → 0.1.1 (build 1)
✓ Build completed
✓ Verified build artifact

Dry run — no files were written.

  Bundle:  dist/MyApp.app
```

`swift build -c release`가 통과했고, `.build/release/MyApp` 바이너리가 실제로 생겼다. 파일 시스템에는 `dist/` 아래 새 디렉터리가 만들어지지 않았고, `AppVersion.swift`도 그대로다.

**5. `relios release patch` — 풀 파이프라인**

```bash
relios release patch
```

```
✓ Preflight passed
✓ Version: 0.1.0 (build 1) → 0.1.1 (build 1)
✓ Build completed
✓ Verified build artifact
✓ Updated version source
✓ Assembled .app bundle
✓ Generated Info.plist
✓ Signed (ad-hoc)
✓ Installed to /Applications/MyApp.app
✓ Launched MyApp

  Bundle:  dist/MyApp.app
  Install: /Applications/MyApp.app
```

이 시점에 `/Applications/MyApp.app`이 떠 있고, `AppVersion.swift`는 `0.1.1`로 갱신됐다. 기존 설치가 없었으므로 backup 라인은 생략됐다.

**6. `relios inspect` — 매니페스트 확인**

```bash
relios inspect
```

```
Latest Release

  App:       MyApp
  Bundle ID: com.example.myapp
  Version:   0.1.1 (build 1)
  Bundle:    dist/MyApp.app
  Install:   /Applications/MyApp.app
  Mode:      assembly
  Signing:   adhoc
  Launched:  yes
  Timestamp: 2026-05-25T10:00:00Z
```

`dist/releases/latest.json`(덮어씀)과 `dist/releases/history/<timestamp>.json`(이어 붙임)이 함께 생성된다.

### 7.2 Xcode 프로젝트 어댑팅 (passthrough 모드)

이미 `.xcodeproj`가 있는 프로젝트에 Relios를 끼우는 경우. SwiftPM과 워크플로우는 같지만 두 군데(`[build].command`와 `[bundle].output_path`)는 반드시 검증해야 한다.

**1. `relios init`의 passthrough 자동 감지**

```bash
cd /path/to/MyXcodeApp   # MyXcodeApp.xcodeproj가 있는 디렉터리
relios init
```

```
✓ Initialized Relios

Created files:
  relios.toml
  AppVersion.swift

Detected:
  project type:  xcodebuild
  binary target: MyXcodeApp
  bundle mode:   passthrough (Xcode project)
  signing:       adhoc (no Developer ID cert in keychain)

Review before first release:
  [app].bundle_id      (currently com.example.myxcodeapp)
  [build].command      (verify scheme name matches your project)
  [bundle].output_path (MUST match where xcodebuild places the .app)

  Note: scheme name was guessed from the .xcodeproj filename.
  If your scheme name differs, update [build].command and
  [bundle].output_path accordingly.
```

생성된 `[build].command`와 `[bundle].output_path`는 다음과 같다.

```toml
[build]
command = "xcodebuild -scheme MyXcodeApp -configuration Release -derivedDataPath build build"

[bundle]
output_path = "build/Build/Products/Release/MyXcodeApp.app"
mode = "passthrough"

[signing]
mode = "keep"
```

**2. scheme 이름 검증이 필요한 이유**

`relios init`은 `.xcodeproj` 파일 이름에서 scheme 이름을 추측한다. 실제 scheme 이름이 다르면 (예: `MyXcodeApp-macOS`) `xcodebuild`는 `xcodebuild: error: The project does not contain a scheme named "MyXcodeApp"` 로 실패한다. 다음으로 확인하라.

```bash
xcodebuild -list -project MyXcodeApp.xcodeproj
```

`Schemes:` 섹션에 표시된 이름을 `[build].command`의 `-scheme` 인자에 그대로 넣는다.

**3. `[bundle].output_path` 정합성**

`-derivedDataPath build`는 산출물을 `build/Build/Products/Release/`로 고정한다. scheme 이름을 바꿨다면 `output_path`의 `.app` 파일명도 동기화해야 한다. 예: scheme이 `MyXcodeApp-macOS`이면 `output_path = "build/Build/Products/Release/MyXcodeApp-macOS.app"`. 불일치하면 `relios release --dry-run`이 "artifact verification" 단계에서 즉시 실패한다.

**4. 서명 모드 선택**

- `signing.mode = "keep"` (기본): Xcode의 서명 설정을 그대로 둔다. Xcode가 Developer ID로 서명하도록 설정돼 있으면 그 결과를 보존한다. Relios는 `codesign`을 호출하지 않는다.
- `signing.mode = "developer-id"`: Relios가 Xcode 결과를 받아 다시 한 번 서명한다. CI에서 키체인을 직접 관리하는 경우, 또는 Xcode의 자동 서명 결과를 신뢰하지 않을 때.
- `signing.mode = "adhoc"`: 로컬 테스트용. Xcode의 서명을 ad-hoc으로 덮어쓴다.

**5. 검증 + 첫 릴리스**

```bash
relios doctor
relios release patch --dry-run   # xcodebuild 실행, .app 존재 검증, 쓰기 없음
relios release patch             # 풀 파이프라인
relios inspect                   # Mode: passthrough 확인
```

### 7.3 Developer ID 서명 한 번 셋업하고 자동 적용시키기

키체인에 Developer ID Application 인증서를 한 번만 등록해 두면, 그 이후 어떤 프로젝트에서 `relios init`을 실행해도 `[signing]` 섹션이 자동으로 채워진다. 두 가지 등록 경로가 있다.

**경로 A — Xcode 경유 (가장 일반적)**

Xcode → Settings → Accounts → 본인 Apple ID 선택 → Manage Certificates → 왼쪽 하단의 `+` → `Developer ID Application` 선택. 이 작업은 유료 Apple Developer Program ($99/year) 가입자만 가능하다. Xcode가 인증서를 생성하면서 동시에 키체인에 등록한다.

**경로 B — `.p12` 파일을 직접 임포트**

이미 `.p12`로 익스포트해 둔 인증서가 있거나, 다른 머신에서 옮겨오는 경우.

```bash
export RELIOS_CERT_PASSWORD='p12를_익스포트할_때_쓴_암호'
relios signing import ~/Downloads/cert.p12
```

```
✓ Imported /Users/me/Downloads/cert.p12 into login.keychain-db
Next: run `relios signing status` to verify, then `relios signing setup`.
```

내부적으로는 `security import cert.p12 -k login.keychain-db -P "$RELIOS_CERT_PASSWORD" -T /usr/bin/codesign`을 실행한다. `-T /usr/bin/codesign`은 `codesign`이 이 키를 쓸 때 추가 권한 다이얼로그가 뜨지 않도록 미리 허용한다.

**검증**

```bash
security find-identity -v -p codesigning
```

```
  1) ABCD1234... "Developer ID Application: Your Name (TEAMID1234)"
     1 valid identities found
```

```bash
relios signing status
```

```
Keychain identities (codesigning):
  • Developer ID Application: Your Name (TEAMID1234) team=TEAMID1234

relios.toml [signing]:
  mode             = adhoc
  identity         = (unset)
  team_id          = (unset)
  ...
```

(아직 `relios.toml`은 ad-hoc 상태다.)

**자동 기입 작동 확인**

이 시점부터 새 프로젝트에서 `relios init`을 실행하면 다음과 같이 나온다.

```
Detected:
  project type:  swiftpm
  binary target: MyApp
  signing:       developer-id (TEAMID1234)
                 Developer ID Application: Your Name (TEAMID1234)
```

생성된 `relios.toml`의 `[signing]` 섹션은 다음과 같이 미리 채워진다.

```toml
[signing]
mode = "developer-id"
identity = "Developer ID Application: Your Name (TEAMID1234)"
team_id = "TEAMID1234"
hardened_runtime = true
entitlements_path = ""
```

이미 `relios init`을 끝낸 프로젝트에서 추후에 mode를 바꾸려면 `relios signing setup`(인터랙티브)을 쓰면 된다. 키체인에 인증서가 여러 개라면 번호로 선택하게 된다.

> 키체인 자동 감지 규칙: Developer ID Application 인증서가 **정확히 한 개**일 때만 자동 기입된다. 0개면 ad-hoc 유지, 2개 이상이면 ad-hoc 유지 + `relios signing setup`을 안내한다.

### 7.4 GitHub Actions 릴리스 워크플로우 스캐폴딩

전제: `relios init`이 끝나 `relios.toml`이 있고, 깃 저장소가 GitHub remote와 연결돼 있다.

**1. workflow 생성**

```bash
relios ci init
```

```
✓ Created .github/workflows/release.yml
✓ Created .github/workflows/ci.yml

Project type: swiftpm
Bundle mode:  assembly

Next steps:
  1. Commit the workflows:
       git add .github/workflows && git commit
  2. Push to trigger CI, or a tag to trigger a release:
       git tag v0.1.0 && git push origin v0.1.0

Workflow steps are generated from relios.toml — enabling `[dmg]`,
`[notarize]`, or `[signing].mode = developer-id` injects the
matching steps. Re-run with `--force` after changing relios.toml.
```

두 파일이 생성된다.

- `.github/workflows/ci.yml` — `push: branches: [main]` + `pull_request` 트리거. `swift build -c release` + (Tests 디렉터리 존재 시) `swift test --parallel`.
- `.github/workflows/release.yml` — `push: tags: ['v*']` + `workflow_dispatch` 트리거. 빌드 → 패키지(zip) → GitHub Release 업로드.

`relios.toml`에서 `[dmg].enabled`, `[notarize].enabled`, `[signing].mode = "developer-id"`를 켜면 그에 맞는 스텝(키체인 임포트, `relios dmg`, `relios notarize`)이 자동으로 release.yml에 주입된다.

**2. `relios ci doctor` — workflow + remote 점검**

```bash
relios ci doctor
```

```
[ok] release workflow present
[ok] ci workflow present
[ok] github remote configured

Status: ready
```

remote가 `git@github.com:user/repo.git` 또는 `https://github.com/user/repo.git` 형태가 아니면 `[fail] github remote configured`가 뜬다. workflow 파일이 없으면 `relios ci init`을 안내한다.

**3. 트리거**

태그 푸시가 가장 흔한 트리거다.

```bash
git tag v0.1.0
git push origin v0.1.0
```

이 시점에 GitHub Actions가 `release.yml`을 실행한다. 워크플로우는 `runs-on: macos-15`에서 돈다. 진행 상황은 GitHub Repo → Actions 탭에서 라이브로 확인.

태그를 잘못 만들어 재실행하고 싶다면 workflow_dispatch도 쓸 수 있다.

```
Repo → Actions → Release → Run workflow → tag: v0.1.0
```

같은 태그에 대해 새 실행을 트리거한다. 이미 같은 이름의 GitHub Release가 있으면 `softprops/action-gh-release`가 그 release를 업데이트한다 (자산은 덮어씌워진다).

### 7.5 GitHub Actions에 Developer ID 서명 시크릿 등록

`[signing].mode = "developer-id"`로 `relios ci init`을 다시 실행하면 release.yml 상단에 다음 주석이 들어가고, 키체인 임포트 스텝이 자동 주입된다.

```
# Developer ID signing enabled ([signing].mode = "developer-id"). Required repo secrets:
#   APPLE_CERTIFICATE           — base64-encoded Developer ID Application .p12
#   APPLE_CERTIFICATE_PASSWORD  — password used when exporting the .p12
#   KEYCHAIN_PASSWORD           — any string; used to lock the temp keychain
```

3개 시크릿을 발급해 등록하는 절차다.

**1. `.p12` 익스포트**

Keychain Access → 왼쪽 `login` 키체인 → `My Certificates` → `Developer ID Application: ...` 선택 → 우클릭 → `Export "Developer ID Application: ..."` → 파일 형식 `Personal Information Exchange (.p12)` → 저장 → 익스포트 암호 입력 (이 암호가 `APPLE_CERTIFICATE_PASSWORD`가 된다).

> 익스포트할 때 인증서 항목 자체가 아니라 그 아래 펼쳐지는 **private key가 포함된** 항목을 선택해야 한다. private key가 없는 인증서는 `.p12`로 익스포트할 수 없다 (Export 메뉴가 회색 처리된다).

**2. base64 인코딩 + 클립보드**

```bash
base64 -i /path/to/cert.p12 | pbcopy
```

이게 `APPLE_CERTIFICATE`에 들어갈 값이다.

**3. `KEYCHAIN_PASSWORD` 생성**

CI에서 임시 키체인을 만들 때 쓰는 락 비밀번호. 보안 가치가 있는 비밀이 아니므로 아무 랜덤 문자열이면 된다.

```bash
openssl rand -base64 24 | pbcopy
```

**4. GitHub 시크릿 등록**

Repo → Settings → Secrets and variables → Actions → `New repository secret`을 3번 반복.

| Name | Value |
|---|---|
| `APPLE_CERTIFICATE` | `.p12`의 base64 결과 |
| `APPLE_CERTIFICATE_PASSWORD` | `.p12` 익스포트 시 입력한 암호 |
| `KEYCHAIN_PASSWORD` | `openssl rand -base64 24` 결과 |

**5. 로컬 드라이런 (선택)**

CI 키체인 임포트 스텝이 실제로 통과할지 로컬에서 검증해 볼 수 있다.

```bash
KEYCHAIN=$TMPDIR/relios-test.keychain-db
KEYCHAIN_PASSWORD='임의값'
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import /path/to/cert.p12 -k "$KEYCHAIN" \
  -P "p12_익스포트_암호" -T /usr/bin/codesign
security find-identity -v -p codesigning "$KEYCHAIN"
# 끝나면 정리
security delete-keychain "$KEYCHAIN"
```

`find-identity`가 `1 valid identities found`로 끝나면 CI에서도 같은 결과가 나온다.

태그를 푸시하면 release.yml의 `Import Developer ID certificate` 스텝이 임시 키체인을 만들고, 빌드/서명이 끝난 뒤 `if: always()`로 키체인을 삭제한다.

### 7.6 Apple 노타라이제이션 활성

서명만으로는 Gatekeeper가 "확인되지 않은 개발자" 경고를 띄운다. 노타라이제이션을 통과해 staple하면 그 경고가 사라지고 "인터넷에서 다운로드한 앱입니다. 여시겠습니까?" 한 번만 뜬다.

**1. App-Specific Password 발급**

appleid.apple.com 로그인 → `Sign-In and Security` → `App-Specific Passwords` → `+ Generate an app-specific password`. 2단계 인증이 활성화된 계정에서만 가능하다. 라벨에는 식별 가능한 이름을 넣어 둔다 (예: `relios-notarize-laptop`).

> **이 화면을 닫으면 같은 비밀번호를 다시 볼 수 없다.** 즉시 복사해 안전한 곳에 둔다. 잃어버리면 같은 라벨의 비밀번호를 revoke하고 새로 발급해야 한다.

형식은 `xxxx-xxxx-xxxx-xxxx`다. 일반 Apple ID 비밀번호는 `notarytool`에서 받아주지 않는다.

**2. `relios.toml`에 노타라이제이션 활성화**

```toml
[notarize]
enabled = true
target = "auto"          # dmg 있으면 dmg, 없으면 zip
timeout_seconds = 3600   # 60분 (기본값)
```

자세한 필드 의미는 Section 5.

**3. release.yml 재생성**

```bash
relios ci init --force
```

`--force`는 기존 workflow 파일을 덮어쓴다. 결과로 release.yml에 다음 스텝이 추가된다.

```yaml
- name: Notarize + staple
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: relios notarize "$ZIP"     # 또는 "$DMG_FILE"
```

**4. 추가 시크릿 3개 등록**

7.5와 같은 방식으로 Repo → Settings → Secrets and variables → Actions에 추가.

| Name | Value |
|---|---|
| `APPLE_ID` | Apple Developer 계정 이메일 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 1단계에서 발급한 `xxxx-xxxx-xxxx-xxxx` |
| `APPLE_TEAM_ID` | 10자 Team ID (인증서의 OU와 같아야 함) |

`APPLE_TEAM_ID`와 `relios.toml`의 `[signing].team_id`가 다르면 `relios notarize`가 `team_id mismatch: signing=XXX vs APPLE_TEAM_ID=YYY` 에러로 즉시 멈춘다. Apple에 헛 제출을 하지 않게 막는 사전 검증이다.

**5. 태그 푸시 → Apple 응답 대기**

```bash
git tag v0.2.0
git push origin v0.2.0
```

`Notarize + staple` 스텝의 CI 로그는 다음과 같이 흐른다.

```
→ Submitting MyApp-v0.2.0.zip to Apple notarization
  (may take 2-15 minutes depending on Apple queue load)
  id: 12345678-abcd-...
  status: In Progress
  status: In Progress
  status: Accepted
✓ Notarized + stapled MyApp-v0.2.0.zip
```

Apple 큐 상태에 따라 5~20분이 보통, 가끔 한 시간을 넘어가기도 한다. `timeout_seconds = 3600`은 이를 흡수하는 기본값이다.

**6. Gatekeeper UX 확인**

GitHub Release에서 받은 zip이나 DMG를 열면 첫 실행 때 `"MyApp"은(는) 인터넷에서 다운로드한 앱입니다. 열어도 되겠습니까?` 한 번만 뜨고, 이후로는 그 다이얼로그가 사라진다. `"Apple은(는) 확인되지 않은 개발자가 만든 ..."` 경고가 뜨면 staple이 실패했거나 zip 안의 `.app`이 staple되지 않은 상태다.

### 7.7 DMG 패키징 활성

**1. 사전조건**

`dmgbuild`는 Python 패키지다. 로컬용은 다음 중 하나.

```bash
pipx install dmgbuild    # 권장 (격리)
# 또는
pip install dmgbuild
```

CI에서는 `relios ci init`이 만든 release.yml에 자동으로 `pip install --break-system-packages dmgbuild` 스텝이 들어간다.

**2. `relios.toml`에 DMG 섹션 추가**

```toml
[dmg]
enabled = true
output_dir = "dist"
background_color = "#FCF5F3"
window_size = [540, 360]
icon_size = 80
```

`volume_name`은 생략하면 앱 이름 (`MyApp`)이 자동으로 들어간다. 배경 이미지 필드는 일부러 없다 — UDZO 압축에서 invisible flag가 보존되지 않는 이슈를 회피하기 위해 단색 배경만 지원한다 (자세한 배경은 Section 1.3.3).

**3. 로컬 DMG 생성**

```bash
relios release patch    # 먼저 .app이 dist/MyApp.app에 있어야 함
relios dmg
```

```
✓ Created dist/MyApp-0.1.2.dmg
```

`AppVersion.swift`가 읽히면 파일명에 버전이 들어가고, 어떤 이유로든 읽히지 않으면 `MyApp.dmg`로 떨어진다. 같은 `output_dir`에 있던 기존 `*.dmg`는 새 빌드 전에 제거된다 (stale DMG 누적 방지).

**4. CI에 DMG 스텝 추가**

```bash
relios ci init --force
```

release.yml에 다음 두 스텝이 자동 주입된다.

```yaml
- name: Install dmgbuild
  run: pip install --break-system-packages dmgbuild
  ...
- name: Create DMG
  run: relios dmg

- name: Record DMG path
  run: |
    DMG_FILE=$(ls dist/*.dmg | head -1)
    echo "DMG_FILE=$DMG_FILE" >> "$GITHUB_ENV"
```

`Publish GitHub Release` 스텝의 `files:`에는 zip과 DMG가 함께 업로드된다.

**5. DMG + notarize 조합**

`[notarize].target = "auto"`(기본)면 DMG가 켜져 있을 때 DMG가 노타라이제이션 대상이 된다. DMG는 ticket을 자체적으로 보유할 수 있으므로 staple이 DMG에 직접 적용된다 (zip은 unzip → 내부 `.app`에 staple → re-zip의 우회 경로).

명시적으로 zip만 노타라이즈하고 싶으면 `[notarize].target = "zip"`으로 지정한다.

### 7.8 롤백 / 재배포

**실수로 잘못 배포했을 때 즉시 되돌리기**

```bash
relios rollback
```

```
✓ Restored from: dist/app-backups/MyApp-0.1.1-build-1-20260524-093012.zip
✓ Installed at:  /Applications/MyApp.app
✓ Launched app
```

`[install].backup_dir`(기본 `dist/app-backups`)의 가장 최근 zip이 복원된다. `release` 명령은 매번 새 설치 직전에 기존 `.app`을 zip으로 묶어 이 디렉터리에 쌓는다 (`[install].keep_backups = 3`이면 최대 3개 유지).

**특정 백업으로 되돌리기**

```bash
ls dist/app-backups/
# MyApp-0.1.0-build-1-20260520-110000.zip
# MyApp-0.1.1-build-1-20260524-093012.zip

relios rollback --to dist/app-backups/MyApp-0.1.0-build-1-20260520-110000.zip
```

rollback도 release처럼 실행 중인 앱을 먼저 종료하고 (`[install].quit_running_app = true`이면), `auto_open = true`면 복원 후 다시 띄운다.

**GitHub Release 되돌리기**

`relios rollback`은 로컬 설치만 다룬다. 이미 푸시된 태그/Release를 되돌리려면 두 가지 선택이 있다.

- 수동 삭제: Repo → Releases → 해당 release → Delete → 그 뒤 태그도 `git push origin :v0.1.1`로 삭제.
- 새 태그로 덮어쓰기: 수정한 코드에 `v0.1.2` 태그를 새로 만들어 푸시. 이전 release는 history에 남지만 사용자는 새 release를 받게 된다.

> 노타라이즈된 빌드는 회수가 불가능하다. Apple 측에서 ticket을 revoke할 수 없으므로, 이미 배포된 빌드의 staple은 영원히 유효하다. 회수가 필요한 보안 이슈라면 새 버전으로 빠르게 덮어쓰는 것이 유일한 방어다.

### 7.9 트러블슈팅 흐름

세 가지 가장 흔한 실패 패턴과 대응.

**A. `stapler exit 66` — CDN 전파 지연**

`notarytool`이 "Accepted"를 반환한 직후에 `stapler staple`이 65 또는 66으로 실패하는 경우. Apple의 ticket이 CDN에 아직 전파되지 않아 stapler가 ticket을 못 가져온 상황이다.

Relios는 이걸 알고 있어 자동으로 3회까지 재시도한다 (각 시도 사이 10초 대기). 로그에 다음과 같이 보인다.

```
xcrun stapler staple ... → exit 66
[retry 2/3 after 10s]
xcrun stapler staple ... → exit 0
✓ Stapled
```

3회 모두 실패하면 `[notarize] failed`로 종료된다. 그 시점의 대응.

```bash
# 5~10분 기다린 뒤 수동으로 다시 시도
xcrun stapler staple dist/MyApp-0.2.0.dmg

# 또는 Apple notary 상태 자체를 확인
xcrun notarytool history \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

영구 실패라면 보통 Apple 측 인프라 이슈다. https://developer.apple.com/system-status/ 에서 Notary Service 상태 확인.

**B. Apple 응답이 30분 넘게 걸릴 때**

기본 `timeout_seconds = 3600`(60분)으로도 모자라면 `notarytool submit --wait`가 timeout으로 죽는다. 큐가 밀려 있을 뿐 제출 자체는 완료된 경우가 많으므로, submission ID를 가지고 별도로 polling할 수 있다.

```bash
# CI 로그에서 'id: <submission-id>' 라인을 찾는다
SUB_ID=12345678-abcd-...

xcrun notarytool info "$SUB_ID" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

`status: Accepted`로 바뀌면 staple만 수동으로 실행하면 된다.

```bash
xcrun stapler staple dist/MyApp-0.2.0.dmg
xcrun stapler validate dist/MyApp-0.2.0.dmg
```

릴리스 자산은 GitHub Releases 페이지에서 수동 교체. 다음 릴리스부터는 `relios.toml`에서 `timeout_seconds = 7200` 식으로 늘리는 것을 고려한다.

**C. Submission ID 추적**

실패한 submission의 로그를 받으려면 ID가 있어야 한다.

```bash
# 전체 히스토리
xcrun notarytool history \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"

# 특정 submission 로그 (왜 invalid인지가 들어 있음)
xcrun notarytool log "$SUB_ID" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

`log` 출력은 JSON이며, `"issues"` 배열에 거부 사유가 들어 있다. 흔한 사유.

- `The signature of the binary is invalid.` — `[signing].mode`가 `developer-id`인지, hardened runtime이 켜져 있는지, 모든 helper/framework가 같은 인증서로 서명됐는지.
- `The executable does not have the hardened runtime enabled.` — `[signing].hardened_runtime = true`로 두고 다시 빌드.
- `The signature does not include a secure timestamp.` — `codesign` 호출에 `--timestamp`가 누락. Relios의 `DeveloperIDSigner`는 기본으로 붙이지만 직접 서명 스크립트를 추가했다면 확인이 필요.

CI 환경에서 submission ID를 잃지 않으려면 release.yml의 노타라이즈 스텝 위에 다음을 추가해 ID를 별도 파일로 저장하는 방법도 있다.

```yaml
- name: Notarize + staple (with ID capture)
  env:
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: relios notarize "$ZIP" 2>&1 | tee notarize.log
- name: Upload notarize log
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: notarize-log
    path: notarize.log
```

`if: always()`로 실패해도 로그를 아티팩트로 받아 분석할 수 있다. submission ID는 `notarize.log`의 `id:` 라인에 있다.

---

이상이 처음 Relios를 들이는 시점부터 Developer ID + DMG + 노타라이제이션까지 가는 표준 경로다. 각 단계는 이전 단계의 산출물을 그대로 받는 구조이므로, 새 기능을 켜고 싶을 때마다 `relios.toml`에 한 섹션을 추가하고 `relios ci init --force`로 workflow를 재생성하면 된다. 도구 자체가 상태를 들고 있지 않으므로 같은 명령은 같은 결과를 낸다.
