# W.Prep DMG 패키징 파이프라인 — 현재 구현 상세 문서

> 이 문서는 W.Prep 프로젝트가 **2026-04** 기준 어떻게 macOS DMG 를 만들고 있는지를 빈틈없이 기록합니다. 앞으로 버전이 올라가거나 구조가 바뀔 때, 이 문서를 **레퍼런스**로 보면 전체 구조를 복원할 수 있도록 작성했습니다.

---

## 0. 한눈에 보기

```
┌─────────────────────────────────────────────────────────────┐
│  트리거                                                       │
│    로컬:  bash scripts/deploy.sh [patch|minor|major]         │
│    CI:   git push origin v*  →  GitHub Actions              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  [1] 프론트엔드 빌드       npm run build → dist/              │
│  [2] Tauri 번들 빌드       cargo tauri build --target <...>  │
│                            → W.Prep.app 생성                  │
│  [3] 코드 서명             codesign --force --sign - --deep  │
│  [4] DMG 패키징 (로컬)     dmgbuild -s dmg-settings.py ...    │
│      DMG 패키징 (CI)       tauri-action(기본 번들러)          │
│  [5] 설치 + 백업           /Applications/W.Prep.app 덮어쓰기  │
│  [6] 실행                  open W.Prep.app                    │
└─────────────────────────────────────────────────────────────┘
```

핵심 설계 포인트 한 줄 요약:

> **배경 이미지와 볼륨 아이콘을 쓰지 않는다** → `.background/`, `.VolumeIcon.icns` 파일 자체가 안 만들어짐 → 숨길 필요도 없고, DMG 창에 이상한 폴더가 안 보임.

---

## 1. 관련 파일 맵

| 파일 | 역할 |
|------|------|
| `scripts/deploy.sh` | 전체 배포 오케스트레이터 (bash) |
| `scripts/dmg-settings.py` | `dmgbuild` 설정 (창 크기, 아이콘 위치, 배경색) |
| `src-tauri/tauri.conf.json` | 공통 Tauri 설정 (productName, identifier, bundle.targets, icons) |
| `src-tauri/tauri.macos.conf.json` | macOS 전용 (minimumSystemVersion, entitlements 경로) |
| `src-tauri/Entitlements.plist` | macOS 보안 권한 (sandbox, network.client, user-selected rw) |
| `src-tauri/Cargo.toml` | Rust 버전/의존성 (bundling-related crate 없음) |
| `src-tauri/icons/icon.icns` | `.app` 번들이 쓰는 앱 아이콘 |
| `src-tauri/icons/dmg-background.png` | **현재는 사용하지 않음** (백업용 레거시 에셋) |
| `.github/workflows/release.yml` | 태그 푸시 시 GitHub Actions 멀티플랫폼 빌드 |
| `package.json` | `version` 필드가 deploy.sh 의 버전 싱크 대상 중 하나 |

> 📌 **버전은 세 곳에 산다**: `tauri.conf.json`, `Cargo.toml`, `package.json`. `deploy.sh`의 `sync_version()`이 셋을 동시에 갱신함.

---

## 2. Tauri 구성 (입력)

### 2.1 `src-tauri/tauri.conf.json` 핵심 부분

```json
{
  "productName": "W.Prep",
  "version": "2.1.3",
  "identifier": "com.wprep.desktop",
  "bundle": {
    "active": true,
    "targets": "all",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ]
  }
}
```

- `identifier`는 반드시 **`com.wprep.desktop`** (`com.wprep.app` 쓰면 macOS가 `.app`을 데이터 디렉터리로 오해함 → commit `f1b26fb`에서 고친 이슈)
- `bundle.targets: "all"`이지만 플랫폼별 런타임 타깃은 CLI `--target` 플래그로 결정됨.
- `bundle.macOS` 하위 DMG 옵션(예: `dmg.background`, `dmg.windowSize`)은 **일부러 비워두고** 있음. 로컬에서는 `dmgbuild`로, CI에서는 `tauri-action` 기본값으로 만들기 때문.

### 2.2 `src-tauri/tauri.macos.conf.json`

```json
{
  "bundle": {
    "macOS": {
      "minimumSystemVersion": "11.0",
      "entitlements": "./Entitlements.plist"
    }
  }
}
```

- 최소 OS: **Big Sur (11.0)**. Intel + Apple Silicon 모두 커버.
- `entitlements`는 상대경로라 `src-tauri/`가 작업 디렉터리일 때 해석됨.

### 2.3 `src-tauri/Entitlements.plist`

```xml
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
```

샌드박스 ON + 필요한 최소 권한만.

---

## 3. 로컬 빌드 — `scripts/deploy.sh`

### 3.1 사용법

```bash
bash scripts/deploy.sh patch              # 2.1.3 → 2.1.4, 풀 파이프라인
bash scripts/deploy.sh minor              # 2.1.3 → 2.2.0
bash scripts/deploy.sh major              # 2.1.3 → 3.0.0
bash scripts/deploy.sh                    # 버전 유지, 리빌드
bash scripts/deploy.sh patch --dry-run    # 빌드만 검증 (설치/DMG 없음, 버전 롤백)
bash scripts/deploy.sh patch --no-dmg     # DMG 생성 스킵
bash scripts/deploy.sh patch --no-launch  # 설치는 하되 실행 안 함
bash scripts/deploy.sh patch --install-path /some/other/path
```

### 3.2 아키텍처 자동 감지

```bash
ARCH=$(uname -m)   # arm64 또는 x86_64
# → TARGET=aarch64-apple-darwin / x86_64-apple-darwin
# → LABEL=arm64 / x64
```

결과적으로 산출물 경로가 아키별로 분리됨:

```
src-tauri/target/<TARGET>/release/bundle/macos/W.Prep.app
src-tauri/target/<TARGET>/release/bundle/dmg/W.Prep_<VERSION>_<LABEL>.dmg
```

### 3.3 6단계 파이프라인

| 단계 | 명령 | 출력 |
|------|------|------|
| 1. 빌드 | `npm run build` + `cargo tauri build --target $TARGET` | `W.Prep.app` |
| 2. 버전 범프(선택) | `sync_version()` → 3 파일 sed/awk | `tauri.conf.json`, `Cargo.toml`, `package.json` 동기화 |
| 3. 서명 | `codesign --force --sign - --deep "$BUILD_APP"` | ad-hoc 서명 (로컬 실행용) |
| 4. DMG | `DMGBUILD_APP_PATH=$BUILD_APP dmgbuild -s scripts/dmg-settings.py "W.Prep" <출력>.dmg` | `W.Prep_<ver>_<arch>.dmg` |
| 5. 설치 | 구 `.app` 백업 → `cp -R` → `/Applications/W.Prep.app` | 설치된 앱 |
| 6. 실행 | `open /Applications/W.Prep.app` | 실행 |

### 3.4 DMG 단계만 자세히 — `create_dmg()` 함수

```bash
create_dmg() {
  local version="$1"
  local dmg_output="${DMG_DIR}/${APP_NAME}_${version}_${LABEL}.dmg"

  # Tauri가 자체 생성한 깨진 DMG 및 bundle_dmg.sh 잔여물 제거
  rm -f "${DMG_DIR}"/*.dmg
  rm -f "${DMG_DIR}"/bundle_dmg.sh
  mkdir -p "$DMG_DIR"

  DMGBUILD_APP_PATH="$BUILD_APP" \
    dmgbuild -s "$DMG_SETTINGS" "$APP_NAME" "$dmg_output" > /dev/null
}
```

> ⚠️ `cargo tauri build`는 기본 번들러로 **깨진 DMG**를 한 번 먼저 만든다. `rm -f "${DMG_DIR}"/*.dmg` 로 반드시 제거한 뒤 `dmgbuild`로 다시 찍어야 함.

### 3.5 서명 정책

- **로컬**: `codesign --sign -` (ad-hoc). 게이트키퍼 우회 불가지만 내 기기에서 실행엔 충분.
- **CI**: `APPLE_CERTIFICATE` + `APPLE_SIGNING_IDENTITY` 시크릿으로 정식 서명, `APPLE_ID`/`APPLE_PASSWORD`/`APPLE_TEAM_ID`로 notarization.

---

## 4. DMG 설정 — `scripts/dmg-settings.py`

`dmgbuild`가 읽는 **유일한 진실의 소스**. 값 하나하나가 의도적으로 선택됨.

```python
import os

# ── 경로 ──
application = os.environ.get(
    'DMGBUILD_APP_PATH',
    'src-tauri/target/aarch64-apple-darwin/release/bundle/macos/W.Prep.app'
)
appname = os.path.basename(application)   # "W.Prep.app"

# ── 볼륨 ──
format = 'UDZO'           # 압축 HFS+
size = None               # 앱 크기 기반 자동 계산
files = [application]
symlinks = {'Applications': '/Applications'}

# (의도적 주석) 볼륨 아이콘 미설정 → .VolumeIcon.icns 미생성
# icon = 'src-tauri/icons/icon.icns'

# ── 창 ──
# (의도적) background_color 사용 → .background.tiff 미생성 → 숨김 파일 제로
background_color = '#FCF5F3'        # 웨딩 블로섬 톤 (웜 크림 핑크)
show_status_bar  = False
show_tab_view    = False
show_toolbar     = False
show_pathbar     = False
show_sidebar     = False
window_rect      = ((200, 120), (540, 360))   # (x,y), (w,h)
default_view     = 'icon-view'
arrange_by       = None

# ── 아이콘 ──
icon_size = 80
text_size = 12
icon_locations = {
    appname:        (150, 155),
    'Applications': (390, 155),
}
```

### 설정값 의미 요약

| 키 | 값 | 왜 |
|----|----|----|
| `format` | `UDZO` | 압축 + 읽기전용, 표준 배포 포맷 |
| `size` | `None` | 너무 크게 잡으면 배포 용량 낭비, `dmgbuild`가 앱 크기 기반으로 자동 산정 |
| `background_color` | `#FCF5F3` | **이미지 대신 단색** — 핵심 트릭 (Problem 1 참조) |
| `icon`(주석처리) | 미설정 | `.VolumeIcon.icns` 를 만들지 않기 위함 |
| `window_rect` | `((200,120),(540,360))` | 모니터 좌상단 200/120 위치에 540×360 창. 작지도 크지도 않은 DMG 인상. |
| `icon_locations` | app (150,155), Applications (390,155) | 창 중앙에 수평 정렬. 드래그 앤 드롭 UX가 직관적. |
| `show_*` | 전부 False | DMG 창을 최대한 깔끔하게 |

---

## 5. CI/CD — `.github/workflows/release.yml`

### 5.1 트리거

```yaml
on:
  push:
    tags: ['v*']
```

`git tag v2.1.3 && git push origin v2.1.3` 하면 작동.

### 5.2 매트릭스

| platform (runner) | target | label |
|-------------------|--------|-------|
| `macos-latest` | `aarch64-apple-darwin` | macOS-arm64 |
| `macos-14` | `x86_64-apple-darwin` | macOS-x64 |
| `windows-latest` | `x86_64-pc-windows-msvc` | Windows-x64 |

> `macos-13` 은 deprecated → `macos-14`로 이전 (commit `61d88a8`)

### 5.3 서명/노터리제이션 시크릿

`tauri-apps/tauri-action@v0.5`에 다음 env가 전달됨:
`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`.

### 5.4 ⚠️ 중요한 한계

**CI는 `dmgbuild`를 쓰지 않음.** `tauri-action`이 Tauri 내장 번들러로 DMG를 만듦 → `dmg-settings.py` 의 창 레이아웃/배경색이 **CI 산출물엔 반영되지 않음**.

> 완벽한 일치가 필요하면, CI 단계에도 `pip install dmgbuild` + `bash scripts/deploy.sh --no-launch` 같은 커스텀 스텝으로 교체해야 함. 현재는 "로컬 수동 릴리스가 주, CI 드래프트는 부"라는 운영 전제.

---

## 6. 산출물 경로 요약

```
src-tauri/target/aarch64-apple-darwin/release/bundle/
├── macos/
│   └── W.Prep.app                          ← 앱 번들
└── dmg/
    └── W.Prep_2.1.3_arm64.dmg              ← 배포 대상 DMG (~13MB)

dist/app-backups/
└── W.Prep-v2.1.2-20260411123045.zip        ← 이전 버전 자동 백업 (최근 3개)
```

---

## 7. 필수 로컬 환경

- Node.js 20+
- Rust stable (`rustup target add aarch64-apple-darwin x86_64-apple-darwin`)
- Xcode Command Line Tools (`codesign`, `/usr/libexec/PlistBuddy`)
- Python 3.8+ with **`dmgbuild`** 설치
  ```bash
  pip install dmgbuild
  # 또는
  pipx install dmgbuild
  ```

이게 없으면 `scripts/deploy.sh`의 4단계에서 실패.

---

## 8. 관련 커밋 히스토리 (중요 지점)

| 커밋 | 내용 |
|------|------|
| `f1b26fb` | `identifier` com.wprep.app → com.wprep.desktop, tauri-action v0→v0.5, macos-14 |
| `61d88a8` | Intel 러너 macos-13 → macos-14 이전 |
| `c34ad9c` | v0.2.0 릴리스 블로커 수정 |
| (미커밋) | `Entitlements.plist` 추가 + `tauri.macos.conf.json`에 entitlements 경로 추가 + release.yml에 Apple 시크릿 배선 |

---

## 9. 검증 체크리스트 (릴리스 직전)

- [ ] `bash scripts/deploy.sh patch --dry-run` 통과
- [ ] 생성된 DMG 더블클릭 → Finder 창 **`.background`, `.fseventsd`, `.VolumeIcon.icns`가 안 보임**
- [ ] 창 크기가 화면에 비해 너무 크지 않음 (540×360)
- [ ] 아이콘 두 개가 수평 정렬 + 배경이 웜 크림 핑크
- [ ] 드래그 앤 드롭으로 `/Applications`에 설치 가능
- [ ] 설치 후 실행 시 "손상됨" 경고 없음 (ad-hoc은 최초 1회 허용 프롬프트 발생 가능)
- [ ] `codesign -dv --verbose=4 /Applications/W.Prep.app` 정상
- [ ] DMG 크기 ~15MB 이하
