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
