# W.Prep DMG 패키징 문서

macOS DMG 를 깔끔하게(숨김 폴더 없이, 적당한 크기로) 만들기 위한 레퍼런스 문서 묶음.

| # | 문서 | 언제 읽나 |
|---|------|-----------|
| 01 | [`01-current-pipeline.md`](./01-current-pipeline.md) | "지금 W.Prep은 정확히 어떻게 DMG 를 만드는가?" 를 알고 싶을 때 |
| 02 | [`02-reusable-guide.md`](./02-reusable-guide.md) | 다른 Tauri/macOS 앱에 똑같은 방식을 적용하고 싶을 때 |
| 03 | [`03-problems-and-fixes.md`](./03-problems-and-fixes.md) | 예전에 겪은 이슈를 다시 만났을 때 / 설계 이유가 궁금할 때 |

## TL;DR
- DMG 생성 도구: **`dmgbuild` (Python)** — `create-dmg` 아님, AppleScript 안 씀
- 설정 파일: `scripts/dmg-settings.py` (창 540×360, 아이콘 2개 수평 배치)
- **배경 이미지 대신 단색** (`#FCF5F3`) + **볼륨 아이콘 없음** → 숨길 파일 자체가 생기지 않음
- 오케스트레이션: `bash scripts/deploy.sh [patch|minor|major]`
- CI는 `tauri-action@v0.5` 사용 (로컬과 레이아웃 불일치, 의도적 타협)
