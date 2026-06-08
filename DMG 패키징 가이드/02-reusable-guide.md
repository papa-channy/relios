# 다른 Tauri(또는 macOS) 앱에서 동일한 방식으로 DMG 만들기 — 가이드

> 목표: **이상한 숨김 폴더가 안 보이고**, **창 크기가 적당하고**, **드래그 앤 드롭이 직관적인** DMG 를, 어떤 macOS 앱에서도 재현할 수 있게 단계별로 안내.

핵심 철학은 하나:

> **숨길 파일을 만들지 말 것**.
> `.background/`, `.VolumeIcon.icns`는 생성된 순간 macOS 15+ 에서 완전히 숨기는 것이 불안정하다. 단색 배경과 앱 번들 자체 아이콘만 쓰면 숨길 파일이 애초에 없다.

---

## 0. 준비물

| 도구 | 설치 |
|------|------|
| Python 3.8+ | 기본 제공 / `brew install python@3.12` |
| `dmgbuild` | `pip install dmgbuild` 또는 `pipx install dmgbuild` |
| Xcode CLT | `xcode-select --install` |
| (앱이 Tauri라면) Node + Rust + tauri-cli | 프로젝트별 설치 |

---

## 1. 디렉터리 뼈대

```
<project-root>/
├── scripts/
│   ├── deploy.sh           # 오케스트레이터
│   └── dmg-settings.py     # dmgbuild 설정
└── src-tauri/              # Tauri 프로젝트면 존재. 일반 앱이면 .app 경로만 알면 됨
    └── target/.../release/bundle/macos/<YourApp>.app
```

---

## 2. `dmg-settings.py` 템플릿 (가장 중요)

프로젝트 이름/경로/색상만 바꿔서 재사용.

```python
import os

APP_NAME = "YourApp"   # ← 바꾸기: 제품명 (확장자 .app 빼고)

# ── 입력 .app 경로 (환경변수로 오버라이드 가능) ──
application = os.environ.get(
    'DMGBUILD_APP_PATH',
    f'src-tauri/target/aarch64-apple-darwin/release/bundle/macos/{APP_NAME}.app'
)
appname = os.path.basename(application)

# ── 볼륨 ──
format = 'UDZO'         # 압축 읽기전용
size = None             # 자동 산정
files = [application]
symlinks = {'Applications': '/Applications'}

# 볼륨 아이콘 ⚠️ 절대 설정 금지
# icon = '...'   ← 이 줄을 켜면 .VolumeIcon.icns가 DMG 루트에 생겨서 Finder에 보임

# ── 창 ──
# ⚠️ 배경은 반드시 '이미지 파일'이 아닌 '색상'으로. 이유는 03-problems-and-fixes.md 참조.
background_color = '#FCF5F3'   # ← 브랜드 색상으로 교체
show_status_bar = False
show_tab_view   = False
show_toolbar    = False
show_pathbar    = False
show_sidebar    = False
window_rect     = ((200, 120), (540, 360))   # 작고 깔끔한 크기
default_view    = 'icon-view'
arrange_by      = None

# ── 아이콘 ──
icon_size = 80
text_size = 12
icon_locations = {
    appname:        (150, 155),
    'Applications': (390, 155),
}
```

### 크기 계산 가이드
- `window_rect` 폭 `W`, 높이 `H`
- 앱 아이콘 x = `W/2 - 120`, Applications x = `W/2 + 120` (간격 240px)
- 둘 다 y = `(H - 아이콘텍스트높이) / 2` 정도
- 540×360이면 (150,155) / (390,155)로 자연스러움

### 배경색은 어떻게 고르나
- 단색이면 OK. 그라디언트/이미지는 이 가이드의 범위를 넘음.
- 앱 아이콘과 **대비가 충분한** 연한 톤을 추천 (#FCF5F3 같은 페일 톤).
- 테스트: `dmgbuild -s dmg-settings.py "Test" /tmp/test.dmg && open /tmp/test.dmg`

---

## 3. `deploy.sh` 템플릿 (핵심만)

W.Prep의 전체 `deploy.sh`는 버전 동기화/백업/설치까지 다 포함하지만, **DMG 만들기 부분만 떼내면** 이렇게 단순화 가능:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="YourApp"
TARGET="aarch64-apple-darwin"    # 또는 x86_64-apple-darwin
LABEL="arm64"
VERSION=$(grep '"version"' src-tauri/tauri.conf.json | head -1 | sed 's/.*: *"\(.*\)".*/\1/')

BUILD_APP="src-tauri/target/${TARGET}/release/bundle/macos/${APP_NAME}.app"
DMG_DIR="src-tauri/target/${TARGET}/release/bundle/dmg"

# 1) 빌드
npm run build
cargo tauri build --target "$TARGET"

# 2) ad-hoc 서명 (로컬 실행용)
codesign --force --sign - --deep "$BUILD_APP"

# 3) Tauri가 만든 깨진 DMG 정리 ⚠️ 반드시 필요
rm -f "${DMG_DIR}"/*.dmg
rm -f "${DMG_DIR}"/bundle_dmg.sh
mkdir -p "$DMG_DIR"

# 4) dmgbuild 로 재생성
DMGBUILD_APP_PATH="$BUILD_APP" \
  dmgbuild -s scripts/dmg-settings.py "$APP_NAME" \
           "${DMG_DIR}/${APP_NAME}_${VERSION}_${LABEL}.dmg"

echo "✓ ${DMG_DIR}/${APP_NAME}_${VERSION}_${LABEL}.dmg"
```

### Tauri가 아닌 일반 macOS 앱

`cargo tauri build` 부분을 원래 빌드 명령으로 바꾸고, `BUILD_APP`을 해당 `.app` 경로로만 맞춰주면 나머지는 동일.

---

## 4. Tauri `tauri.conf.json` 권고 설정

```json
{
  "productName": "YourApp",
  "identifier": "com.yourcompany.desktop",    // ⚠️ *.app / *.data 피할 것
  "bundle": {
    "active": true,
    "targets": "all"
    // dmg.* 하위 설정을 여기 넣지 말기
    // → dmgbuild 가 주된 소스가 되어야 함
  }
}
```

`src-tauri/tauri.macos.conf.json`:

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

`Entitlements.plist` (필요한 최소권한만, 앱 특성에 맞게 조정):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
```

---

## 5. CI/CD — 로컬과 동일한 DMG 를 CI에서도 만들고 싶다면

`tauri-action` 은 **내장 번들러**를 쓰기 때문에 `dmg-settings.py`가 반영되지 않는다. 동일하게 가고 싶으면 다음 중 하나:

### 옵션 A — 커스텀 잡으로 교체 (권장, 단 복잡)

```yaml
- name: Setup Python + dmgbuild
  run: pip install dmgbuild

- name: Build .app
  run: |
    npm ci
    npm run build
    cargo tauri build --target ${{ matrix.target }} --bundles app

- name: Sign .app
  run: codesign --force --sign - --deep "src-tauri/target/${{ matrix.target }}/release/bundle/macos/YourApp.app"

- name: Create DMG with dmgbuild
  env:
    DMGBUILD_APP_PATH: src-tauri/target/${{ matrix.target }}/release/bundle/macos/YourApp.app
  run: |
    dmgbuild -s scripts/dmg-settings.py "YourApp" \
      "src-tauri/target/${{ matrix.target }}/release/bundle/dmg/YourApp_${{ github.ref_name }}_${{ matrix.label }}.dmg"

- name: Upload to Release
  uses: softprops/action-gh-release@v2
  with:
    files: src-tauri/target/${{ matrix.target }}/release/bundle/dmg/*.dmg
    draft: true
```

`--bundles app`으로 Tauri가 DMG를 만들지 않도록 지시한 뒤, 직접 `dmgbuild`로 찍는 구조.

### 옵션 B — 현재 W.Prep 방식 (간편, 레이아웃은 타협)

`tauri-action@v0.5` 를 그대로 쓰고 CI 산출물은 레이아웃이 덜 깔끔해도 감수. 로컬 `deploy.sh` 산출물이 "공식" 이라는 운영 합의.

---

## 6. 검증 루틴

릴리스 전 반드시:

```bash
# 1) DMG 열어서 눈으로 확인
open path/to/YourApp_x.y.z_arm64.dmg

# 2) 마운트 상태에서 Finder에 보이는 파일이 .app 과 Applications 심볼릭링크뿐인지 확인
#    ← ".background", ".fseventsd", ".VolumeIcon.icns" 보이면 실패

# 3) 마운트된 볼륨의 실제 내용 (숨김 포함)
ls -la /Volumes/YourApp/

# 4) 서명 확인
codesign -dv --verbose=4 /Volumes/YourApp/YourApp.app
```

**Finder에서 보이면 안 되는 것:**
- `.background` 폴더
- `.fseventsd` 폴더
- `.VolumeIcon.icns` 파일
- `.DS_Store` 파일 (이건 원래부터 안 보여야 정상)

만약 보인다면 → `03-problems-and-fixes.md` 체크.

---

## 7. 트러블슈팅 퀵 시트

| 증상 | 우선 의심 |
|------|-----------|
| `.background` 폴더가 보임 | `background_image` 쓰고 있음 → `background_color`로 바꿔라 |
| `.VolumeIcon.icns` 가 보임 | `icon = ...` 주석 처리 확인 |
| DMG에 여러 파일이 뜸 | `cargo tauri build`가 만든 구 DMG를 지우지 않음 → `rm -f *.dmg` |
| 창이 너무 큼 | `window_rect` 의 (w,h) 줄이기. 540×360 권장 |
| 아이콘이 배경 밖에 걸림 | `icon_locations` 좌표가 `window_rect` 범위 안에 있는지 확인 |
| "손상됨" 경고 | 서명 누락 또는 ad-hoc → notarization 필요 |
| CI에서 레이아웃이 다름 | tauri-action 은 dmgbuild 를 안 씀 → 옵션 A로 전환 |

---

## 8. 이 가이드의 스코프 밖 (별도 조사 필요)

- 커스텀 배경 **이미지** 사용 + 숨김 파일 회피 (가능은 하지만 macOS 버전별 테스트 부담 큼)
- 공식 Apple Developer ID 서명 + notarization 자동화 세부 (별도 공식 문서 참고)
- Mac App Store 제출용 pkg 빌드 (DMG와 파이프라인이 다름)
- Sparkle 등 자동 업데이트 프레임워크 배선
