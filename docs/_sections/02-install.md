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
