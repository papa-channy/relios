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
