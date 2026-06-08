# Relios 종합 가이드

> macOS 앱 릴리스 자동화 CLI. 로컬 `.app` 빌드부터 Developer ID 서명, DMG 패키징, Apple 노타라이제이션, GitHub Actions 릴리스 워크플로우 스캐폴딩까지 한 도구로.

이 문서는 현재(v0.3.5 기준) Relios가 어떻게 동작하는지, 각 명령어가 내부적으로 무엇을 하는지, 실제 macOS 앱 패키징/배포에 어떻게 활용하는지를 빠짐없이 정리한다. 다음 작업(다듬기, 새 기능 추가, 다른 앱에 적용)을 위한 단일 진입점 역할.

---

## 목차

1. [개요와 설계 철학](#1-개요와-설계-철학)
2. [설치 및 요구사항](#2-설치-및-요구사항)
3. [핵심 개념](#3-핵심-개념)
4. [CLI 명령어 레퍼런스](#4-cli-명령어-레퍼런스)
5. [`relios.toml` 스펙](#5-reliostoml-스펙)
6. [내부 아키텍처](#6-내부-아키텍처)
7. [엔드 투 엔드 워크플로우](#7-엔드-투-엔드-워크플로우)
8. [Doctor 규칙과 문제 진단](#8-doctor-규칙과-문제-진단)
9. [테스트 전략](#9-테스트-전략)
10. [확장 포인트와 로드맵](#10-확장-포인트와-로드맵)
11. [부록](#11-부록)

---

## 1. 개요와 설계 철학

### 1.1 Relios란 무엇인가

Relios는 macOS 앱의 로컬 릴리스 파이프라인을 한 줄로 압축하는 CLI다. SwiftPM이든 Xcode 프로젝트든 `relios release patch` 한 번이면 빌드, 버전 범프, `.app` 조립(혹은 통과), 코드 서명, 설치, 실행까지 끝난다. v0.3 부터는 Developer ID 서명, DMG 패키징, Apple 노타라이제이션, GitHub 릴리스 업로드, 그리고 GitHub Actions 워크플로우 스캐폴딩까지 한 도구가 책임진다.

도구 그 자체는 작다. 한 개의 Swift 실행 바이너리, 한 개의 `relios.toml`, 그리고 버전 상수가 든 `AppVersion.swift` 한 파일. 그러나 그 뒤에는 macOS 패키징/배포 과정에서 누적된 수많은 실패 경험과, 그 경험을 "다시는 같은 실수를 하지 않게" 도구 수준에 박아둔 결정들이 깔려 있다.

### 1.2 왜 만들어졌나 — 해결하려는 문제

macOS 앱 한 번 배포하려면 개발자는 평균적으로 이런 일을 반복한다.

1. `swift build -c release` 또는 `xcodebuild`
2. `.app` 디렉터리 구조 만들기 (`Contents/MacOS`, `Contents/Resources`, `Info.plist`)
3. 바이너리 복사, 아이콘 복사, 리소스 번들 복사
4. `codesign` 한두 줄
5. `/Applications`에 있던 이전 버전 백업 (지우면 롤백 불가)
6. `pkill` 또는 `osascript -e 'quit app'`
7. 새 `.app`을 `/Applications`로 복사
8. `open -a` 로 실행
9. Developer ID 배포라면: 다시 서명, `dmgbuild`, `xcrun notarytool submit`, 결과 폴링, `stapler staple`, GitHub 릴리스 업로드

이 흐름은 매번 같지만 매번 한두 군데가 어긋난다. 버전 상수를 `AppVersion.swift`에서만 올리고 `Info.plist`는 안 고쳤다, `codesign --deep` 순서가 틀려 헬퍼가 먼저 서명됐다, `dmgbuild` 결과 DMG 안에 `.DS_Store`와 `.fseventsd`가 보인다, 노타라이제이션은 통과했는데 staple을 깜빡했다, CI 러너가 `macos-13` 단종으로 죽었다 — 모두 실제로 겪었던 일이다.

해결할 수 있는 방법은 두 가지뿐이다. (a) Fastlane 같은 거대한 메타 도구를 들이거나, (b) 매번 같은 셸 스크립트를 복붙해 프로젝트마다 약간씩 다른 변종을 갖거나. Relios는 그 사이의 빈자리를 노린다. **하나의 macOS 앱에 한 번 설정하면, 같은 명령으로 매번 같은 결과가 나오는 작은 도구.** 그게 전부다.

### 1.3 핵심 설계 철학

#### 1.3.1 Assembly vs Passthrough — 빌드 산출물의 소유권을 명확히

SwiftPM은 실행 바이너리 한 개만 만들어 준다. `.app` 디렉터리 구조, `Info.plist`, 아이콘 배치는 도구가 해야 한다. 반면 Xcode는 이미 완성된 `.app`을 내놓는다. 같은 단계를 두 번 다시 만들면 둘 사이가 미묘하게 어긋난다.

Relios는 이걸 두 개의 모드로 갈라 둔다.

- **assembly** (SwiftPM): 바이너리를 받아서 Relios가 `.app`을 처음부터 조립한다. `Info.plist`도 Relios가 쓴다. 서명도 Relios가 한다.
- **passthrough** (Xcode/XcodeGen): `xcodebuild`가 만든 `.app`을 손대지 않고 그대로 받는다. `Info.plist` 재생성도, 번들 재조립도 하지 않는다. 기본 서명 모드는 `keep` — Xcode가 한 서명을 보존한다.

같은 워크플로우, 같은 `relios release` 명령. 그러나 내부에서 누가 `.app`의 주인인지를 절대 헷갈리지 않는다. `relios init`이 프로젝트 마커(`Package.swift`, `.xcodeproj`, `project.yml`)를 보고 자동으로 모드를 결정한다.

#### 1.3.2 한 번 등록하면 자동 입력 — 키체인을 신뢰한다

Developer ID 서명/노타라이제이션 설정은 손으로 입력하면 반드시 실수한다. `Developer ID Application: Foo Bar (TEAMID12)` 같은 문자열을 외워서 `relios.toml`에 적을 사람은 없다.

Relios는 그 대신 `relios init`이 키체인을 한 번 훑어서 발견한 Developer ID 인증서를 자동으로 채워 넣는다. Team ID는 인증서의 OU 필드에서 추출한다. Apple ID 와 App Store Connect API 키도 마찬가지로 환경 변수/키체인을 우선 본다. 사용자가 입력하는 정보는 도구가 알아낼 수 없는 것들(앱 이름, bundle id, 배포 채널)뿐이다.

이 철학은 단순한 편의가 아니다. **타이핑이 줄어든 만큼 오타로 인한 서명 실패가 줄어든다.**

#### 1.3.3 숨길 파일을 만들지 마라 — DMG 가이드에서 가져온 교훈

이 프로젝트의 모태가 된 W.Prep DMG 패키징 작업에서 얻은 가장 비싼 교훈은 이것이다.

> **숨기려 하지 말고, 만들지 마라.** macOS HFS+의 invisible flag는 UDZO 압축 변환 과정에서 보존되지 않는다. `chflags hidden`, `SetFile -a V` 어느 쪽도 신뢰할 수 없다. 문제를 해결하려 들지 말고, 문제가 생기는 파일 자체를 만들지 않도록 설계를 바꿔라.

Relios의 DMG 파이프라인은 이 원칙을 그대로 따른다. 배경 이미지 대신 단색을 쓰고, 볼륨 아이콘을 지정하지 않는다. 그 결과 `.background/`, `.VolumeIcon.icns`가 애초에 생성되지 않는다. 같은 사고방식이 다른 곳에도 퍼져 있다 — 실패할 가능성이 있는 단계는 회피 가능한지 먼저 묻고, 회피할 수 없을 때만 방어 코드를 쓴다.

#### 1.3.4 결정적(deterministic) 빌드 — AppleScript 대신 dmgbuild, ditto

같은 입력은 같은 결과를 내야 한다. CI 러너에서 됐다가 로컬에서 안 되거나, 또는 그 반대인 상황은 디버깅 비용을 비대칭적으로 키운다.

Relios의 도구 선택은 이 기준으로 정해져 있다.

- **DMG 생성**: `dmgbuild` (Python). AppleScript로 Finder 창을 띄워 아이콘을 끌어다 놓는 `create-dmg` 방식은 헤드리스 환경에서 비결정적이다. `dmgbuild`는 `.DS_Store`를 바이너리로 직접 합성하므로 GUI 의존이 없다.
- **번들 복사**: `cp -R` 대신 `ditto`. xattr, 리소스 포크, 심볼릭 링크가 보존된다. 서명된 `.app`을 `cp -R`로 옮기면 서명이 깨질 수 있다.
- **앱 종료**: `osascript`의 `tell application "X" to quit` 대신 NSRunningApplication 기반 시퀀스. AppleScript의 권한 다이얼로그를 회피한다.

비결정적인 단계를 단 하나라도 끼워 두면, 같은 도구가 다른 결과를 내기 시작하는 순간 사용자는 도구 자체를 의심하게 된다. 그 신뢰를 잃지 않는 것이 핵심이다.

#### 1.3.5 Validation과 Doctor — 실패는 빨리, 명시적으로

릴리스 파이프라인의 가장 큰 비용은 "20분짜리 빌드 마지막 단계에서 실패하는" 일이다. 노타라이제이션 제출 직전에 entitlements 오타를 발견하거나, DMG 업로드 직전에 GitHub 토큰 권한이 모자란 걸 알게 되는 일.

Relios는 두 층의 사전 검증을 둔다.

- `relios doctor`: 명령 실행 전에 환경/설정/도구체인을 점검한다. 6+개의 정적 규칙이 통과해야 release가 시작된다. 도구가 PATH에 있는지, `Info.plist` 패턴이 맞는지, 키체인에 서명 인증서가 살아 있는지.
- 파이프라인 내부의 preflight: release가 시작되어도 각 단계 진입 전에 산출물을 재검증한다. dry-run은 "쓰기 직전까지 모든 검증을 끝내고 멈춤"이 정의다.

설정 파일에 잘못된 값이 들어가는 걸 막을 수는 없다. 그러나 **잘못된 값으로 인한 실패는 첫 5초 안에** 나도록 강제할 수 있다.

### 1.4 다른 도구 대비 위치

- **Fastlane**: 강력하지만 거대하다. Ruby 런타임, gem 의존성, 수십 개의 lane 액션. 단일 앱 1인 개발자가 들이기엔 과하다. Relios는 단일 실행 바이너리 하나로 끝난다.
- **수제 셸 스크립트**: 가장 흔한 출발점이지만, 프로젝트마다 변종이 생기고 macOS 버전 업데이트마다 한 줄씩 고쳐야 한다. 디버깅한 교훈이 다른 프로젝트로 전파되지 않는다. Relios는 그 교훈들을 도구 수준에 박는다.
- **Xcode 자체 Archive + Organizer**: GUI 의존, CI 비친화, 그리고 SwiftPM-only 프로젝트는 사용 불가.
- **`xcrun notarytool` 직접 호출**: 가능은 하지만, "build → sign → DMG → submit → poll → staple → upload" 시퀀스의 상태 머신을 사용자가 매번 짜야 한다.

Relios는 이 사이의 "단일 앱 × 1인 개발자 × 로컬 + GitHub Actions" 구간을 차분히 채운다. 더 큰 도구가 잘하는 일을 다시 하지 않고, 더 작은 스크립트가 자주 틀리는 일을 자동으로 막는다. 그게 이 도구의 존재 이유다.


---

## 2. 설치 및 요구사항

이 섹션은 Relios CLI를 머신에 설치하고, 실행에 필요한 최소 시스템 요구사항과 선택적 도구·계정 의존성을 정리합니다. App-Specific Password 발급 등 워크플로우 단계는 Section 7에서 다루고, 여기서는 "무엇이 설치되어 있어야 하는가"에만 집중합니다.

### 2.1 Relios 설치

Relios는 단일 바이너리(`relios`)로 배포됩니다. 권장 경로는 Homebrew tap이며, 직접 빌드도 동일하게 지원합니다.

#### 2.1.1 Homebrew tap (권장)

```bash
brew tap papa-channy/relios
brew install relios
```

Homebrew는 의존성 격리, 업그레이드, 제거 경로(`brew upgrade relios`, `brew uninstall relios`)를 모두 관리해주므로 일반 사용자에게는 이 방법을 권장합니다.

#### 2.1.2 소스 빌드 (From source)

최신 main 브랜치나 특정 태그를 직접 빌드하려는 경우 사용합니다. Swift toolchain이 설치되어 있어야 합니다.

```bash
git clone https://github.com/papa-channy/relios.git
cd relios
swift build -c release
cp .build/release/relios /usr/local/bin/relios
```

빌드 산출물은 `.build/release/relios` 경로에 생성되며, PATH에 포함된 디렉터리(예: `/usr/local/bin`, `~/.local/bin`)로 복사하면 어디서든 호출할 수 있습니다.

#### 2.1.3 설치 확인

```bash
relios --version
relios --help
```

`--version`은 현재 바이너리 버전을 출력하고, `--help`는 사용 가능한 서브커맨드 목록을 보여줍니다. 두 명령이 모두 정상적으로 출력되면 설치는 완료입니다.

### 2.2 시스템 요구사항

| 항목 | 최소 요구사항 | 출처 |
|---|---|---|
| OS | macOS 13 (Ventura) 이상 | `Package.swift` (`.macOS(.v13)`) |
| Swift toolchain | swift-tools-version 6.0 이상 | `Package.swift` 첫 줄 |
| Xcode Command Line Tools | 설치 필수 (`xcode-select --install`) | `swift`, `codesign` 제공 |
| 디스크 공간 | 약 200MB (소스 빌드 시 빌드 캐시 포함) | — |

`min_macos`는 사용자가 만드는 앱(`relios.toml`의 `[app].min_macos`)을 의미하며, Relios 자체는 macOS 13 이상에서 동작합니다. Xcode Command Line Tools만 설치되어 있어도 SwiftPM(assembly) 모드의 모든 기능과 ad-hoc 서명은 동작합니다.

### 2.3 선택적 의존성

기능 사용 여부에 따라 추가 도구가 필요합니다. 아래 매트릭스는 "어떤 기능을 쓸 때 무엇이 필요한가"를 한 표로 정리한 것입니다.

| 기능 | 필요한 도구 | 설치 명령 / 비고 |
|---|---|---|
| SwiftPM 빌드 (assembly) | `swift` (CLT 포함) | `xcode-select --install` |
| Xcode 빌드 (passthrough) | 풀 Xcode + `xcodebuild` | App Store 또는 developer.apple.com |
| Ad-hoc 코드 서명 | `codesign` (CLT 포함) | 기본 제공 |
| Developer ID 서명 | `codesign` + 키체인의 Developer ID 인증서 | Apple Developer Program 필요 |
| DMG 패키징 | Python 3 + `dmgbuild` | `pipx install dmgbuild` 또는 `pip install dmgbuild` |
| 노타라이제이션 | `xcrun notarytool` (Xcode 13+) | 풀 Xcode 필요, CLT 단독 불가 |
| 노타라이제이션 스테이플 | `xcrun stapler` (Xcode 포함) | 풀 Xcode 필요 |

핵심 주의사항 두 가지:

- **`xcodebuild`와 `notarytool`은 풀 Xcode가 필요합니다.** Command Line Tools만 설치된 상태에서는 호출이 실패합니다. 둘 중 하나라도 사용하려면 App Store에서 Xcode를 설치한 뒤 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`로 활성 toolchain을 전환하세요.
- **`dmgbuild`는 Python 패키지입니다.** 시스템 Python에 직접 설치하는 것보다 `pipx install dmgbuild`로 격리하는 것을 권장합니다. DMG 출력을 생성하지 않는 워크플로우라면 설치하지 않아도 됩니다.

### 2.4 Apple Developer 계정 요구사항

배포 형태에 따라 필요한 계정 등급이 다릅니다. 로컬 개발용으로만 쓴다면 계정은 전혀 필요 없습니다.

| 배포 시나리오 | Apple Developer 계정 | 추가 자격 증명 |
|---|---|---|
| 로컬 ad-hoc 서명 (`signing.mode = "adhoc"`) | 불필요 | 없음 |
| Xcode 서명 유지 (`signing.mode = "keep"`) | Xcode가 사용 중인 인증서 기준 | Xcode의 기존 설정에 위임 |
| Developer ID 배포 서명 | **유료 Apple Developer Program 가입 ($99/year)** | 키체인에 "Developer ID Application" 인증서 |
| 노타라이제이션 | Developer ID와 동일 | **App-Specific Password** (notarytool 인증용) |

App-Specific Password 발급 절차와 키체인 저장 방법은 Section 7(워크플로우)에서 다룹니다. 여기서는 노타라이제이션을 사용할 계획이라면 (1) 유료 Developer Program 가입, (2) Developer ID Application 인증서, (3) App-Specific Password가 모두 필요하다는 점만 기억하세요.

### 2.5 첫 검증 (sanity check)

설치가 끝났다면 어떤 프로젝트 디렉터리에서도 다음 두 명령으로 환경을 검증할 수 있습니다.

```bash
relios --help     # 서브커맨드 목록이 출력되는지 확인
relios doctor     # 현재 프로젝트의 릴리스 준비 상태 6개 항목 점검
```

`relios doctor`는 프로젝트 타입, 스펙 유효성, 버전 소스 파일, 빌드 도구(`swift` 또는 `xcodebuild`) PATH, 설치 경로, 서명 도구(`codesign`)의 존재 여부를 차례로 점검합니다. `relios.toml`이 없는 디렉터리에서 실행하면 안내 메시지와 함께 종료하므로, 신규 프로젝트에서는 `relios init`을 먼저 실행한 뒤 `doctor`를 돌리면 됩니다. 구체적인 사용법은 Section 4(CLI)에서 다룹니다.


---

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


---

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


---

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


---

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


---

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


---

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


---

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


---

## 10. 확장 포인트와 로드맵

이 섹션은 Relios의 "지금 못 하는 것"과 "이런 식으로 손대면 추가할 수 있다"를 문서화합니다. 현재 명령 사용법은 Section 4, 내부 아키텍처는 Section 6을 참고하세요. 여기서는 한계를 인정한 다음, 코드베이스의 어디를 건드려야 새 기능을 안전하게 얹을 수 있는지 패턴 단위로 설명합니다. 마지막에는 다음 단계 후보(Phase 2-4c 이후)와 변경 시 권장 dogfood 흐름을 정리합니다.

### 10.1 현재 알려진 한계

Relios 1.x는 "단일 개발자 macOS 앱의 Apple Silicon 단일 슬라이스 DMG 배포"를 가장 잘 처리하도록 설계되어 있습니다. 그 범위를 벗어나는 시나리오는 의도적으로 빠져 있거나, 부분 구현된 상태입니다.

| 영역 | 현재 상태 | 영향 |
|------|-----------|------|
| 매트릭스 빌드 (arm64 + x86_64) | 미지원. `relios release`는 단일 슬라이스만 빌드 | Intel Mac 호환 필요한 배포는 수동 `lipo` 필요 |
| PKG 배포 | 미지원. DMG만 산출 | `.pkg` 인스톨러 요구하는 엔터프라이즈 시나리오 불가 |
| App Store Connect API key | 미지원. Apple ID + App-Specific Password만 | 큰 조직에서 keychain 공유/회전 불편 |
| Sparkle / auto-update | 통합 없음 | 사용자가 직접 appcast.xml과 EdDSA 키 관리 필요 |
| Developer ID Installer signing | 미지원 | PKG 추가 시 함께 필요 |
| Mac App Store 제출 | 미지원 (entitlements/sandbox/category 가정 없음) | MAS 빌드는 별도 도구 사용 |
| `relios release` git working tree mutation | 항상 버전 source 파일을 수정·커밋 | CI에서 `--ci` 플래그 없이는 working tree가 더럽혀짐 |
| `xcodebuild` 모드 test step 자동 감지 | `ci.yml` 렌더러에 TODO 주석으로만 존재 | xcodebuild 프로젝트는 사용자가 수동으로 step 활성화 |

위 한계 중 일부(매트릭스 빌드, PKG, API key)는 10.6에서 후보로 다룹니다. 나머지는 의도된 스코프 외(MAS) 또는 우선순위 낮은 nice-to-have(Sparkle, 배경 이미지)입니다.

### 10.2 확장 패턴: 새 명령 추가

새 subcommand를 추가하는 표준 흐름입니다. 기존 명령(`BuildCommand`, `NotarizeCommand` 등)이 모두 이 패턴을 따릅니다.

1. **CLI 레이어 파일 생성** — `Sources/ReliosCLI/Commands/XxxCommand.swift`. `ParsableCommand` 채택, `@Option`/`@Flag`로 인자 선언, `run()`에서 Core 타입을 인스턴스화·호출.
2. **루트 명령에 등록** — `Sources/ReliosCLI/ReliosCommand.swift`의 `subcommands:` 배열 끝에 `XxxCommand.self` 추가. 알파벳 순이 아닌 사용 빈도/연관성 순으로 유지합니다.
3. **Core 도메인 슬라이스 작성** — `Sources/ReliosCore/Xxx/`에 디렉터리 생성. 비즈니스 로직은 `Xxx` 타입(예: `XxxRunner`, `XxxBuilder`)에, 옵션은 별도 `XxxOptions` 구조체로 분리. ProcessRunner/FileSystem 의존성은 생성자 주입.
4. **에러 타입** — `XxxError: Error, CustomStringConvertible`을 같은 슬라이스에 두고, `shortReason: String`과 `shortFix: String` 계산 프로퍼티를 구현. `NotarizeError.swift`를 참고하면 톤이 일관됩니다.
5. **테스트** — `Tests/ReliosCoreTests/Xxx/`에 슬라이스별 테스트 디렉터리 생성. 기존 헬퍼(`FakeProcessRunner`, `TemporaryDirectory`, fixture 로더)를 재사용. CLI 레이어 테스트는 보통 불필요(인자 파싱은 ArgumentParser가 보장).

체크리스트:
- [ ] CLI 파일이 Core 타입만 호출하고 비즈니스 로직을 포함하지 않음
- [ ] 에러 메시지가 shortReason/shortFix 패턴으로 통일
- [ ] `--help` 출력의 `abstract`/`discussion`이 한 줄로 명확함
- [ ] subcommand 등록 후 `swift run relios xxx --help`로 표시 확인

### 10.3 확장 패턴: 새 [section] 추가

`relios.toml`에 새 섹션을 도입할 때 건드리는 파일들입니다.

1. **섹션 타입** — `Sources/ReliosCore/Spec/XxxSection.swift`. `Decodable`, `Equatable`, `Sendable` 채택. 필드는 `let` + Optional로 시작해 기본값을 명시.
2. **ReleaseSpec에 연결** — `Sources/ReliosCore/Spec/ReleaseSpec.swift`에 프로퍼티 추가. 신규 섹션이 선택적이라면 `Optional<XxxSection>`으로 두고, `CodingKeys`에도 등록.
3. **Init 스켈레톤** — `relios init`이 새 섹션을 자동 생성해야 한다면 `Sources/ReliosCore/Init/SpecSkeleton.swift`와 `SpecSkeletonWriter.swift`를 함께 업데이트. 헤더 주석에 "왜 이 섹션이 있는지" 1~2줄 추가.
4. **Validation 규칙** — 새 섹션이 의미 있는 사전조건을 가진다면 `Sources/ReliosCore/Validation/Rules/XxxReadinessRule.swift`를 추가하고 `DoctorRunner` 또는 해당 명령 파이프라인에 등록. 기존 `NotarizeReadinessRule`, `DMGReadinessRule`이 참고용으로 좋습니다.
5. **테스트** — `SpecDecodingTests`에 TOML 라운드트립 케이스 추가(최소 fixture + 누락 시 동작). 새 readiness rule이 있다면 별도 unit test 디렉터리.

체크리스트:
- [ ] 섹션이 optional이면 누락 시 동작이 명확(기본값/스킵/에러 중 무엇?)
- [ ] `SpecSkeletonWriter` 산출물이 사람이 읽기 쉬운 한국어 주석 포함
- [ ] `SpecDecodingTests`에 "정상", "누락", "잘못된 타입" 세 케이스
- [ ] 관련 ValidationRule이 doctor에서 호출됨

### 10.4 확장 패턴: 새 Doctor 규칙 추가

Doctor는 두 갈래(`relios doctor`, `relios ci doctor`)로 나뉘어 있고 각각 다른 rule 디렉터리를 씁니다.

| 종류 | 위치 | 용도 |
|------|------|------|
| 환경/스펙 readiness | `Sources/ReliosCore/Validation/Rules/` | 로컬 환경, 자격증명, 스펙 정합성 |
| CI 워크플로우 검사 | `Sources/ReliosCore/CI/Rules/` | `.github/workflows/*.yml` 존재, GitHub remote, secrets |

1. **규칙 파일 생성** — 위 표에서 적합한 디렉터리에 `XxxRule.swift` 추가.
2. **프로토콜 구현** — `ValidationRule`을 채택하고 `evaluate(context:) -> RuleResult`를 구현. RuleResult는 pass/warn/fail/skip 중 하나를 반환하며, fail/warn에는 사람이 읽을 수 있는 메시지를 동봉.
3. **등록** — `DoctorCommand.swift`의 rules 배열 또는 `CICommand.DoctorSubcommand`의 rules 배열에 추가. 순서는 실행 순서이자 출력 순서이므로, 빠르고 결정적인 규칙을 앞쪽에 둡니다.
4. **테스트** — pass/warn/fail/skip 모든 분기를 단위 테스트. `ValidationContext`는 임시 디렉터리·fake spec으로 조립할 수 있어 외부 의존성 없이 검증 가능합니다.

체크리스트:
- [ ] 메시지가 "왜 실패했는가"와 "어떻게 고치는가"를 모두 포함
- [ ] 외부 명령 호출이 있다면 ProcessRunner 주입으로 mock 가능
- [ ] skip 조건(예: 섹션 미정의)이 명확하고 silent

### 10.5 확장 패턴: release.yml에 새 스텝 주입

`relios ci init`이 생성하는 `release.yml`은 `ReleaseWorkflowRenderer`가 문자열 템플릿으로 조립합니다. 새 스텝을 끼워넣을 때 건드릴 곳은 한 군데지만, 따라야 할 규칙이 있습니다.

1. **렌더러 수정** — `Sources/ReliosCore/CI/ReleaseWorkflowRenderer.swift`에서 적절한 위치에 조건부 블록 추가. 기존 `dmgEnabled`, `devIDSigning`, `notarize` 분기가 패턴 예시입니다. 항상 `RenderContext`에서 플래그를 받아 분기하고, 하드코딩하지 마세요.
2. **헤더 주석 갱신** — 생성되는 yaml 최상단에 필수 secrets 목록을 주석으로 둡니다. 새 스텝이 secret을 요구하면 여기에 추가.
3. **액션 SHA 핀** — 외부 action(`actions/checkout`, `softprops/action-gh-release` 등)을 새로 도입할 경우, 렌더러 상단의 정적 상수에 SHA 핀 형태로 선언(`@v4` 같은 mutable tag 금지). Section 4.9.3의 SHA 핀 정책 준수.
4. **테스트** — `CIInitRunnerTests`에 다음 두 검증을 추가합니다.
   - 새 플래그가 켜졌을 때 스텝 문자열이 yaml에 등장하는지
   - 생성된 yaml이 parse 가능한지(smoke parse)
5. **dogfood 검증** — 10.7 흐름으로 실제 워크플로우가 도는지 한 번은 돌려봅니다.

체크리스트:
- [ ] 새 스텝이 조건부이고 기본 off (기존 사용자 워크플로우를 깨지 않음)
- [ ] secret 이름이 헤더 주석과 일치
- [ ] 외부 action은 SHA 핀
- [ ] CIInitRunnerTests에 on/off 두 케이스 모두 존재

### 10.6 확장 후보 제안

다음은 우선순위 순이 아닌, 영역별 후보 목록입니다. 각 항목은 "한 명이 한 주에 끝낼 수 있는가" 기준으로 난이도를 표기했습니다.

| 후보 | 난이도 | 진입점 | 비고 |
|------|--------|--------|------|
| App Store Connect API key 지원 | 중 | `NotarizerCredentials`를 sum type(`.appSpecific` / `.apiKey`)으로 확장, `notarize` 섹션에 `keyId`/`issuerId`/`keyPath` 필드 추가 | `xcrun notarytool`이 이미 양쪽 모드 지원. CLI 인자 `--key`/`--key-id`/`--issuer` 추가 |
| 매트릭스 빌드 (arm64 + x86_64) | 상 | `BuildCommand`에 `--arch arm64,x86_64`, 빌드 후 `lipo -create`로 universal 산출. CI는 `strategy.matrix`로 분리 후 합치는 별도 job | 노타라이즈 대상이 universal app 단일이라 하류 변화는 작음 |
| PKG / Developer ID Installer | 상 | `[pkg]` 섹션 + `pkgbuild`/`productbuild` 래퍼. 새 `PKGBuilder` 슬라이스 | DMG와 직교하므로 둘 다 산출 가능하게 |
| Sparkle appcast 생성 | 중 | `dist/releases/`를 스캔해 `appcast.xml` 생성하는 `relios appcast` 명령 | EdDSA 서명은 사용자가 자기 키로 별도 처리 |
| `relios release --ci` 플래그 | 하 | `ReleaseOptions`에 `ci: Bool` 추가, true면 `VersionSourceUpdater` 호출과 커밋 단계 스킵, 태그명을 직접 truth로 사용 | CI에서 working tree 더럽힘 제거. 가장 빠른 win |
| DMG 배경 이미지 옵션 | 하 | `DMGSection`에 `backgroundImage: String?` 추가, `DMGSettingsRenderer`에 conditional | 가이드 철학상 단색 권장이지만 옵션은 무해 |
| `relios ci doctor` 강화 (drift) | 중 | 현재 `release.yml`을 다시 렌더해 byte-diff 비교. 다를 경우 warn | "재생성하면 어떻게 다른지" 출력이 핵심 UX |
| 사용자 메시지 다국어화 | 중 | 메시지 카탈로그 도입(`Sources/ReliosSupport/Localization.swift`), `RELIOS_LANG=ko` 등 env로 전환 | 가이드 문서는 이미 한국어, CLI 메시지는 현재 영어 |

각 항목은 Section 10.2~10.5의 확장 패턴 중 하나 이상에 매핑됩니다(예: PKG는 10.2 + 10.3 + 10.5 모두, --ci 플래그는 10.2만).

### 10.7 변경 시 dogfood 권장 흐름

Relios 변경이 실제 사용자 경험을 깨지 않는지 확인하는 흐름입니다. 작은 버그 수정은 1~2단계만, 새 기능 추가는 5단계 전부를 권장합니다.

| 단계 | 동작 | 통과 기준 |
|------|------|----------|
| 1 | Relios 자체 테스트: `swift test` | 모든 타깃 그린 |
| 2 | `relios.toml`을 가진 검증용 macOS 앱(예: workspace-launcher)에 로컬 빌드 바이너리로 dogfood (`relios doctor`, `relios release --dry-run` 등) | 새 동작이 의도대로, 기존 동작이 회귀 없음 |
| 3 | Relios에 새 버전 태그 푸시 → Homebrew tap 자동 업데이트(release.yml) | tap 저장소의 formula가 새 SHA로 갱신됨 |
| 4 | 검증 앱에서 `brew upgrade relios` 후 `relios ci init --force` | 새 워크플로우 파일이 변경된 렌더러 결과로 갱신됨 |
| 5 | 검증 앱에 태그 푸시 → 풀 CI 파이프라인(빌드 → 서명 → 노타라이즈 → 스테이플 → DMG → 릴리스 게시) | DMG가 GitHub Releases에 게시되고 사용자 흐름으로 설치·실행 가능 |

이 흐름은 "Relios가 자기 자신으로 릴리스되고, 그 릴리스가 실제 앱을 릴리스한다"는 dogfood 루프를 보장합니다. 새 확장 패턴(10.2~10.5)을 따랐다면 1~2단계가 자동으로 그린이어야 하며, 3~5단계는 SHA 핀, secret 이름, 워크플로우 호환성 같은 실환경 이슈를 잡아냅니다.

확장 작업의 PR을 올릴 때는 위 5단계 중 어디까지 검증했는지를 description에 명시하는 것을 관례로 둡니다. 5단계까지 통과하지 못한 변경은 main에 머지하지 않고, 검증용 앱이 적합하지 않은 변경(예: PKG 도입)은 별도 검증 앱을 일시적으로 만들어 같은 5단계를 돌립니다.


---

## 11. 부록

본문에 흩어진 레퍼런스성 자료를 한곳에 모은 빠른 참조입니다. 명령 사용법의 의미는 Section 4(CLI)·Section 5(Spec)에서, 트러블슈팅 스토리는 Section 9에서 다루며, 여기서는 이미 알고 있는 사람이 손에 두고 보는 치트시트 수준의 요약만 둡니다.

### 11.1 GitHub Actions 핀된 액션 SHA 레퍼런스

Relios가 생성하는 워크플로우는 모든 서드파티 액션을 **SHA로 핀**합니다. 태그(`@v6`)는 같은 태그로 재공개될 수 있는 반면 커밋 SHA는 불변입니다. 소스: `Sources/ReliosCore/CI/ReleaseWorkflowRenderer.swift`, `CIWorkflowRenderer.swift`의 `private static let` 상수.

| 액션 | 버전 | SHA | 용도 |
|---|---|---|---|
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` | 코드 체크아웃 |
| `maxim-lobanov/setup-xcode` | v1.7.0 | `ed7a3b1fda3918c0306d1b724322adc0b8cc0a90` | `xcode-version: latest-stable` |
| `actions/cache` | v5.0.4 | `668228422ae6a00e4ad889ee87cd7109ec5666a7` | SwiftPM 캐시 (`ci.yml` 전용) |
| `softprops/action-gh-release` | v3.0.0 | `b4309332981a82ec1c5618f44dd2e27cc8bfbfda` | GitHub Release 생성 |

**업데이트 절차** — 핀은 두 렌더러에 같은 상수가 중복 선언되어 있으므로 둘 다 바꿔야 양 워크플로우에 일관되게 반영됩니다.

```bash
# 1. 새 태그의 커밋 SHA 확인
gh api repos/actions/checkout/git/refs/tags/v6.0.3 --jq '.object.sha'
# 2. 두 렌더러의 상수 교체 (주석의 버전 라벨도 함께)
# 3. 스냅샷 테스트 → `relios ci init --force`로 사용자 프로젝트 재생성
```

> 워크플로우 YAML을 직접 편집해 SHA를 올려도 다음 `--force` 시 렌더러 값으로 덮어쓰입니다. 항상 렌더러를 진실의 소스로 둘 것.

### 11.2 키체인 명령 치트시트

Relios 파이프라인이 내부적으로 호출하는 것과 동일한 형태입니다. `security` 명령은 위치 인자 순서가 비대칭이라 자주 헷갈립니다.

```bash
# ── 조회 ─────────────────────────────────────────────
security find-identity -v -p codesigning                            # 전체 identity
security find-identity -v -p codesigning <keychain-path>            # 특정 키체인 한정
security list-keychains -d user                                     # 현재 search list

# ── 키체인 생성 / 잠금 ───────────────────────────────
security create-keychain      -p "$PW" relios-signing.keychain-db
security set-keychain-settings -lut 21600 relios-signing.keychain-db    # 6시간 후 자동 잠금
security unlock-keychain      -p "$PW" relios-signing.keychain-db

# ── .p12 임포트 + 비대화식 서명 허용 ─────────────────
security import cert.p12 -k relios-signing.keychain-db -P "$P12_PW" -T /usr/bin/codesign
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: -s -k "$PW" relios-signing.keychain-db
# ↑ partition-list가 빠지면 CI에서 GUI 프롬프트 대기 후 타임아웃

# ── search list 앞에 추가 / 기본만 남기기 ────────────
security list-keychains -d user -s relios-signing.keychain-db \
  $(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s login.keychain-db

# ── 삭제 (잡 종료 시 `if: always()`) ──────────────────
security delete-keychain relios-signing.keychain-db

# ── codesign / spctl 검증 ────────────────────────────
codesign -dv --verbose=4 YourApp.app                       # 서명 메타데이터
codesign --verify --deep --strict --verbose=2 YourApp.app  # 강한 검증
spctl -a -t exec -vv YourApp.app                           # Gatekeeper 평가
#   accepted source=Notarized Developer ID  ← stapled + notarized
#   accepted source=Developer ID            ← signed only
#   rejected source=no usable signature     ← ad-hoc 또는 미서명
```

### 11.3 노타라이제이션 명령 치트시트

`xcrun notarytool`은 Xcode 13+에서만 제공됩니다. CLT 단독 설치엔 없음 (`NotarizeError.notarytoolNotFound`). 아래 명령은 모두 `--apple-id`/`--password`/`--team-id` 3종 인증을 받습니다 — 로컬에선 `notarytool store-credentials <profile>` 후 `--keychain-profile <profile>` 한 줄로 줄일 수 있습니다.

```bash
# ── 제출 + 인라인 대기 ─────────────────────────
xcrun notarytool submit YourApp.zip \
  --apple-id "$APPLE_ID" --password "$APP_PW" --team-id "$TEAM_ID" \
  --wait --timeout 3600s
#   --wait: 진행 라인을 stdout으로 흘림 (Relios는 패스스루, v0.3.2+)
#   --timeout 3600s = 60분 (기본값 인상 이유는 11.5)

# ── 상태 / 로그 / 히스토리 ─────────────────────
xcrun notarytool info    <submission-id> --apple-id … --password … --team-id …
xcrun notarytool log     <submission-id> --apple-id … --password … --team-id …   # Invalid/Rejected 상세
xcrun notarytool history --apple-id … --password … --team-id …

# ── stapler ────────────────────────────────────
xcrun stapler staple    YourApp.app           # .dmg / .pkg 도 동일
xcrun stapler validate  YourApp.app
#   ⚠ .zip 은 validate 대상 아님 — zip을 풀고 내부 .app에 대해 실행 (v0.3.5에서 수정)
```

**흔한 exit code**

| code | 의미 | 대응 |
|---|---|---|
| 0 | 성공 | — |
| 65 / 66 | Apple CDN 전파 지연 (티켓이 아직 안 퍼짐) | 재시도 (Relios v0.3.4+ 자동) |
| 76 | 이미 stapled | 무시 (멱등) |
| 1 | 일반 실패 | `xcrun notarytool log <id>` |

### 11.4 DMG 패키징 가이드 참조

레포 루트 `DMG 패키징 가이드/`는 W.Prep 프로젝트에서 끌어온 외부 레퍼런스로, Relios의 DMG 코드가 따른 설계 결정의 근거 문서입니다.

| 파일 | 내용 |
|---|---|
| `01-current-pipeline.md` | W.Prep의 실제 DMG 파이프라인 (Tauri + `deploy.sh` + `dmgbuild`) |
| `02-reusable-guide.md` | 다른 앱에 적용하는 단계별 가이드, `dmg-settings.py` 템플릿 |
| `03-problems-and-fixes.md` | 사례별 실패와 해결 (macOS 15+의 `.background/`, `.VolumeIcon.icns` 노출 등) |

**Relios가 흡수한 부분** — `Sources/ReliosCore/DMG/DMGSettingsRenderer.swift`, `DMGBuilder.swift`

| 가이드 권고 | Relios 구현 |
|---|---|
| 배경은 단색 (`.background/` 회피) | 렌더러가 `background_color`만 출력 |
| 볼륨 아이콘 금지 (`.VolumeIcon.icns` 회피) | `icon = ...`를 영구 주석 처리 |
| `dmgbuild`(Python) 채택, AppleScript 회피 | `DMGBuilder`가 `dmgbuild`만 호출 |
| 빌더 호출 전 stale DMG purge | `DMGBuilder.purgeExistingDMGs(in:)` |
| 아이콘 정렬 공식 `x = W/2 ± 120` | 렌더러가 `appX = w/2 - 120` 등으로 계산 |

**흡수하지 않은 부분** — Tauri 통합 전체(`cargo tauri build`, 3중 버전 동기화, 멀티플랫폼 매트릭스)는 범위 바깥. Entitlements.plist 자동 생성도 안 함 (`[bundle].entitlements_path`가 가리키는 파일을 그대로 사용).

### 11.5 Apple 노타라이제이션 관측 시간 데이터

`xcrun notarytool submit --wait`의 대기 시간은 Apple Notary 큐 깊이에 전적으로 의존합니다. 이 세션에서 관측한 실측치.

| 케이스 | 시간 | 비고 |
|---|---|---|
| 큐가 비어 있을 때 | 약 17초 | 최단 관측치 (주말 새벽) |
| 정상 범위 | 5~20분 | 2025~2026 평일 낮 |
| 정체 | 50분+ | 제출 ID `04819c28...`에서 53분 관측 |
| Relios 기본 timeout | 60분 (`--timeout 3600s`) | v0.3.3부터 |

**60분으로 잡은 이유** — 30분 기본은 정체 시 정상 제출도 죽이는 사례가 누적됨. Apple 정체는 보통 1시간 내 회복하고, 실제로 거부되는 제출(`Rejected`/`Invalid`)은 5분 내 결과가 떨어지므로 정상 케이스에 비용 추가 없음. **실시간 큐 상태**는 https://developer.apple.com/system-status/ 의 *Developer ID Notary Service*에서 확인 — 노란색/빨간색이면 평소 5분짜리도 1시간 갈 수 있음.

### 11.6 에러 코드 인덱스

Relios 도메인 에러는 각 모듈의 `*Error.swift`에 정의되며 CLI는 `shortReason` + `shortFix`로 출력합니다.

| 모듈 | 파일 | 케이스 |
|---|---|---|
| Init | `Init/InitError.swift` | notSwiftPMProject, writeFailed |
| Spec | `Spec/SpecLoadError.swift` | missing, unreadable, malformed |
| Version | `Version/VersionSourceError.swift` | unreadable, version/buildPatternUnmatched, unparseableSemver/Build |
| Build | `Build/BuildError.swift` | processFailed, nonZeroExit, binaryNotFound |
| Bundle | `Bundle/BundleError.swift` | binaryUnreadable, plistWriteFailed |
| Signing | `Signing/SigningError.swift` | processFailed, nonZeroExit, missingDeveloperIDConfig |
| DMG | `DMG/DMGError.swift` | disabled, appMissing, dmgbuildNotFound/Failed, writeFailed |
| Notarize | `Notarize/NotarizeError.swift` | disabled, artifactMissing, unsupportedArtifact, missingCredentials, teamIDMismatch, notarytoolNotFound, submissionFailed, stapleFailed, repackFailed |
| Install | `Install/InstallError.swift` | backup/terminate/install/launchFailed |
| Release | `Release/ReleaseError.swift` | 13 케이스 (단계별 surface error) |
| Rollback | `Rollback/RollbackError.swift` | noBackupsFound, backupNotFound, unzipFailed, install/terminateFailed |
| CI | `CI/CIError.swift` | specMissing, workflowExists, writeFailed |

> `ReleaseError`는 surface error. 파이프라인 안에서 `BuildError`/`VersionSourceError`/`SigningError` 등 도메인 에러는 모두 `ReleaseError.<step>`로 번역됩니다. CLI 레이어는 `ReleaseError`만 스위치하므로 새 도메인 에러 추가 시 번역 누락 주의.

**외부 명령 exit code**

| 명령 | code | 의미 |
|---|---|---|
| `codesign` | 1 / 2 | 일반 실패 (identity 없음, 잠긴 키체인 등) / 잘못된 인자 |
| `xcodebuild` | 65 / 66 | 빌드 실패 / 잘못된 destination·scheme |
| `notarytool submit` | 0 / 1 | 큐 접수 / 인증·네트워크 실패 또는 Rejected |
| `stapler staple` | 0 / 65·66 / 76 | 성공 / CDN 전파 지연 (자동 재시도) / 이미 stapled |
| `dmgbuild` | 0 / 1 | 성공 / 실패 (stderr가 정보의 거의 전부) |
| `hdiutil` | 49152 | 일반 실패 (메모리·디스크·권한) |

**GitHub Actions step exit 1**은 *현재 step만* 실패시킵니다. 같은 잡의 후속 step 중 `if: always()` / `if: failure()`가 붙은 것은 여전히 실행 (Relios의 키체인 cleanup이 이 패턴).

### 11.7 유용한 외부 링크

**Apple Developer**

| 링크 | 용도 |
|---|---|
| https://developer.apple.com/account | Team ID 확인, Developer ID Application 인증서 발급 |
| https://appleid.apple.com/account/manage/section/security | App-Specific Password 생성 (`APPLE_APP_SPECIFIC_PASSWORD`) |
| https://developer.apple.com/system-status/ | Notary Service 가동/정체 상태 |
| https://developer.apple.com/documentation/security/hardened_runtime | Hardened Runtime entitlement 레퍼런스 |
| https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution | 노타라이즈 공식 문서 |

**도구 문서**

| 링크 | 용도 |
|---|---|
| https://dmgbuild.readthedocs.io/ | `dmgbuild` 설정 옵션 |
| https://github.com/softprops/action-gh-release | Release 액션 입력/출력 |
| https://github.com/maxim-lobanov/setup-xcode | `xcode-version` 사용 가능 값 |
| https://github.com/actions/checkout | `ref`/`fetch-depth`/`submodules` |
| https://github.com/actions/cache | 캐시 키 전략 |
| `man xcrun notarytool` (또는 `--help`) | 설치된 Xcode 기준 최신 notarytool 문서 |
| `man codesign`, `man security` | 키체인·서명 명령 정식 레퍼런스 |

### 11.8 버전 히스토리 (Relios 자체)

`git tag --sort=-creatordate` 기준.

| 버전 | 날짜 | 핵심 변경 |
|---|---|---|
| **v0.1.0-alpha** | 2026-04-12 | 초기 공개 — 로컬 `.app` 파이프라인 (SwiftPM, ad-hoc, 백업/설치/실행) |
| **v0.1.0** | 2026-04-12 | 릴리스 자동화 + Homebrew tap 갱신 |
| **v0.1.1** | 2026-04-12 | Xcode 프로젝트 passthrough 지원, 파이프라인 정제 |
| **v0.2.0** | 2026-04-16 | CI 스캐폴딩(`relios ci init`) + DMG(`relios dmg`) + Developer ID 모드/자동 감지 |
| **v0.3.0** | 2026-04-16 | Apple 노타라이제이션 도입 (`relios notarize`, release.yml 자동 삽입) |
| **v0.3.1** | 2026-04-16 | release.yml이 `$ZIP`/`$DMG_FILE` 명시적 경로 export → 글로빙 제거 |
| **v0.3.2** | 2026-04-16 | notarytool 진행 라인 실시간 스트리밍 |
| **v0.3.3** | 2026-04-16 | notarize timeout 30분 → 60분 |
| **v0.3.4** | 2026-04-16 | `stapler staple` exit 65/66 자동 재시도 (CDN 전파 지연) |
| **v0.3.5** | 2026-04-16 | zip 대상 validate 수정 — 내부 `.app`을 검증 |

> v0.2.0 ~ v0.3.x가 같은 날짜에 몰린 것은 노타라이제이션을 실제 Apple Notary와 부딪혀가며 빠르게 반복한 결과입니다.


---

