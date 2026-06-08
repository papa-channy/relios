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
