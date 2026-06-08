# 우리가 겪었던 문제들과 해결 기록 (DMG 편)

> 이 문서는 W.Prep DMG 패키징 중 실제로 맞닥뜨렸던 이슈들을 시간 순/원인 순으로 정리한 "장애 보고서 + 해결 노트" 입니다. 다음에 같은 함정에 빠지지 않도록, 그리고 다른 프로젝트에 적용할 때 어떤 선택이 "의도된 설계" 인지 알 수 있도록 남깁니다.

---

## 문제 1. DMG에 `.background`, `.fseventsd` 폴더가 Finder에 보임

### 증상
- `create-dmg` / `hdiutil convert`로 DMG를 만들면, 사용자가 DMG를 더블클릭했을 때 Finder 창에 `.background/`, `.fseventsd/` 같은 **점(.)으로 시작하는 폴더**가 보임
- 앱 아이콘과 Applications 심볼릭링크만 있어야 할 자리에 잡동사니가 뜸
- macOS 15 Sequoia 에서 특히 심각

### 원인
HFS+ 파일 속성(invisible flag, `chflags hidden`, `SetFile -a V`)이 **UDZO 압축 변환 과정에서 보존되지 않음**. 즉 쓰기 가능한 DMG 에서 숨겨놓은 파일이, 압축 읽기전용 DMG 로 변환될 때 속성이 날아감.

### 시도했지만 실패한 것들
- `SetFile -a V .background` — 변환 후 재노출
- `chflags hidden .background` — 메타데이터에는 남지만 Finder가 무시
- `.fseventsd` 삭제 후 재생성 — 시스템이 자동으로 다시 만듦
- AppleScript로 창 세팅 — 타이밍/권한 이슈 + 위의 속성 손실 문제 미해결

### 최종 해결 ✅
**숨길 파일을 애초에 만들지 않는다.**

1. 배경은 **이미지가 아닌 단색**으로: `background_color = '#FCF5F3'`
   - → `.background/` 폴더 자체가 생성되지 않음
2. 볼륨 아이콘을 **설정하지 않는다**: `# icon = ...` (주석 처리)
   - → `.VolumeIcon.icns` 파일이 생성되지 않음
3. `.fseventsd` 는 시스템이 자동 생성하지만, `dmgbuild`가 최종 DMG를 빌드할 때 만드는 워킹 디렉터리에서 자연 소멸 (압축 후엔 흔적 없음)

이 세 가지를 지키면 **마운트된 볼륨에 보여야 할 것만 보이는** 상태가 된다.

### 교훈
- macOS의 "파일 숨기기" 메커니즘은 DMG 파이프라인에서 **신뢰하지 말 것**.
- 문제를 해결하려 들지 말고, **문제가 생기는 파일 자체를 만들지 않도록 설계**를 바꾸는 게 더 확실함.

---

## 문제 2. `.VolumeIcon.icns` 가 Finder에 보임

### 증상
DMG 볼륨 아이콘(사이드바에서 보이는 마운트된 드라이브 아이콘)을 커스텀하려고 `create-dmg --volicon icon.icns` 또는 `dmgbuild`의 `icon = '...'` 옵션을 쓰면, DMG 루트에 `.VolumeIcon.icns` 가 숨김파일로 들어가는데, **위와 같은 이유로 Finder에 노출**됨.

### 해결 ✅
**볼륨 아이콘 설정을 포기**한다. `dmg-settings.py`에서:

```python
# icon = 'src-tauri/icons/icon.icns'   ← 주석 처리 유지
```

볼륨 아이콘이 기본값(내장 하드 드라이브 아이콘)이 되지만, DMG 창 안의 앱 아이콘은 `.app` 번들 자체의 `icon.icns`가 정상 표시되므로 사용자 경험에는 거의 영향 없음.

### 트레이드오프
사이드바/데스크탑 마운트 아이콘이 브랜드 아이콘이 아님. 대부분의 유저는 DMG를 마운트하자마자 자동으로 창이 뜨므로 신경 쓰지 않음.

---

## 문제 3. AppleScript 기반 창 레이아웃의 타이밍 레이스

### 증상
`create-dmg` / 수제 hdiutil 스크립트가 AppleScript 로 Finder 창 크기, 아이콘 위치를 지정할 때:
- Finder가 DMG를 인식하기 전에 스크립트가 실행 → 실패
- `.DS_Store` 가 잠겨 있어 쓰기 실패
- `delay N` 늘려도 CI 러너마다 결과 다름

### 해결 ✅
**`dmgbuild` (Python) 채택.** `dmgbuild`는:
- `.DS_Store`를 **바이너리로 직접 합성** (AppleScript 없이)
- Finder, osascript 에 의존하지 않음
- 헤드리스(CI 포함) 환경에서도 결정적으로 동작

이 한 번의 도구 선택이 위의 1, 2, 3을 동시에 해결하는 결정타.

---

## 문제 4. `cargo tauri build`가 먼저 만든 "깨진" DMG가 남음

### 증상
`cargo tauri build`는 bundle target에 `dmg`가 포함되면 **Tauri 기본 번들러로 DMG를 한 번 만든다**. 우리가 원하는 레이아웃과 다른 DMG. 그 뒤 `dmgbuild`를 돌리면 같은 디렉터리에 파일 두 개가 공존해서 어느 게 진짜 배포용인지 혼동.

### 해결 ✅
`deploy.sh`의 `create_dmg()`에서 **dmgbuild 호출 직전에 청소**:

```bash
rm -f "${DMG_DIR}"/*.dmg
rm -f "${DMG_DIR}"/bundle_dmg.sh     # Tauri가 남긴 보조 스크립트
mkdir -p "$DMG_DIR"
```

선택지로 `--bundles app,updater` 플래그로 아예 DMG를 Tauri가 만들지 않게 할 수도 있지만, 현재는 단순히 **덮어쓰기** 전략으로 가고 있음.

---

## 문제 5. 앱이 `/Applications` 에 설치되었는데도 macOS가 **데이터 디렉터리**로 취급

### 증상
설치 후 `/Applications/W.Prep.app`을 더블클릭해도 앱이 실행되지 않고, Finder가 폴더로 열어버림. 또는 Spotlight에서 앱으로 잡히지 않음.

### 원인
`identifier`가 `com.wprep.app` 이었음. macOS가 `*.app` 패턴의 bundle identifier 를 특수 케이스로 취급하면서 번들을 **앱이 아닌 컨테이너(데이터 폴더)** 로 잘못 해석한 사례.

### 해결 ✅ (commit `f1b26fb`)
`tauri.conf.json`:
```diff
- "identifier": "com.wprep.app",
+ "identifier": "com.wprep.desktop",
```

### 교훈
**bundle identifier 마지막 세그먼트로 `.app`, `.data`, `.cache` 같이 macOS가 특별 취급할 수 있는 단어는 피하기.** `.desktop`, `.macos`, `.client`, 또는 제품 코드네임이 안전.

---

## 문제 6. CI 러너 `macos-13` 단종

### 증상
`runs-on: macos-13` 잡이 GitHub Actions에서 "deprecated" 경고 후 실패.

### 해결 ✅ (commit `61d88a8`)
`.github/workflows/release.yml` 에서 Intel 러너를 `macos-13` → `macos-14`로 이전.

---

## 문제 7. `tauri-action@v0` 이 Tauri v2 번들 API 와 호환 안 됨

### 증상
GitHub Actions에서 `tauri-apps/tauri-action@v0` 사용 중 "unknown bundle option" 관련 에러.

### 해결 ✅ (commit `f1b26fb`)
`v0` → `v0.5` 로 업그레이드. v0.5는 Tauri v2 를 정식 지원.

---

## 문제 8. 버전이 세 곳에 중복 저장되어 동기화 실수 빈발

### 증상
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `package.json`

세 파일에 `version` 이 각각 존재. 하나만 업데이트하고 릴리스하면 About 창과 DMG 파일명이 어긋남.

### 해결 ✅
`scripts/deploy.sh` 의 `sync_version()` 함수가 세 파일을 동시에 sed/awk 로 수정. `deploy.sh patch|minor|major` 만 쓰면 영구히 이 실수가 사라짐.

```bash
# BSD sed (macOS) 는 0,/pattern/ 미지원 → awk 사용
awk -v ver="$version" '/^version = "/ && !done { sub(...); done=1 } 1' Cargo.toml > tmp && mv tmp Cargo.toml
```

### 교훈
macOS 기본 `sed`는 GNU sed 와 플래그가 다르다는 점도 잊지 말 것. awk 로 우회하거나 `gsed` 쓰기.

---

## 문제 9. CI 가 `dmgbuild` 를 안 쓰는 불일치

### 현재 상태 (미해결, 의도적 타협)
로컬(`deploy.sh`)은 `dmgbuild` + `dmg-settings.py` 사용.
CI(`tauri-action@v0.5`)는 Tauri 내장 번들러 사용.

→ **두 파이프라인이 같은 레이아웃의 DMG 를 만들지 못함.**

### 운영 합의
지금은 **로컬 수동 릴리스 산출물이 공식 배포본**. CI 는 draft 릴리스를 만들지만 실제 배포는 로컬 DMG 를 업로드.

### 향후 개선안
`02-reusable-guide.md` §5의 "옵션 A"처럼 CI 단계에 Python + `dmgbuild` 를 추가하고, Tauri 는 `.app` 만 만들게 한 뒤(`--bundles app`) 우리 스크립트로 DMG 를 찍는 커스텀 잡으로 교체.

---

## 체크리스트 — "이 증상 본 적 있다" 자가진단

| 증상 | 참조 |
|------|------|
| 점으로 시작하는 폴더가 DMG 창에 보임 | 문제 1 |
| `.VolumeIcon.icns` 보임 | 문제 2 |
| CI에서는 되는데 로컬에서는 AppleScript 에러 | 문제 3 |
| DMG 두 개가 나옴 / 잘못된 DMG 가 업로드됨 | 문제 4 |
| `/Applications/*.app` 을 macOS가 폴더로 열음 | 문제 5 |
| CI 에서 `macos-13` deprecation 경고 | 문제 6 |
| tauri-action 에서 unknown bundle option | 문제 7 |
| DMG 파일명 버전과 About 다이얼로그 버전 불일치 | 문제 8 |
| 로컬 DMG 와 CI DMG 의 창 레이아웃이 다름 | 문제 9 |

---

## 핵심 교훈 Top 5

1. **숨기려 하지 말고, 만들지 마라.** HFS+ invisible flag는 UDZO 변환에서 날아간다.
2. **AppleScript 기반 DMG 레이아웃은 비결정적**이다. `dmgbuild` 처럼 `.DS_Store` 를 바이너리로 합성하는 도구로 가라.
3. **`cargo tauri build` 가 만든 DMG 는 지우고 덮어쓰라.** 안 그러면 엉뚱한 파일이 배포됨.
4. **bundle identifier 마지막 세그먼트는 `.app` 피하라.** macOS가 특수 취급한다.
5. **버전은 한 곳에서 파생되게**. 수동으로 여러 파일을 고치면 반드시 어긋난다.
