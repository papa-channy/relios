# Relios

Stop manually building, copying, and installing `.app` files.

Relios is a local release pipeline for macOS apps. One command replaces your entire build-sign-install workflow.

```
relios release patch
```

## Before / After

**Without Relios:**

```bash
swift build -c release
mkdir -p dist/MyApp.app/Contents/MacOS
cp .build/release/MyApp dist/MyApp.app/Contents/MacOS/
# ... generate Info.plist, copy icon, copy resources ...
codesign --force --deep --sign - dist/MyApp.app
cp -R dist/MyApp.app /Applications/MyApp.app
open -a /Applications/MyApp.app
```

**With Relios:**

```bash
relios release patch
```

## Quick start

```bash
relios init
relios doctor
relios release patch
```

That's it. `init` detects your project type and generates a `relios.toml` config + `AppVersion.swift` version source. `doctor` validates everything. `release` runs the full pipeline.

## What you get

- **One-command release** — build, version bump, package, sign, install, launch
- **Automatic backup + rollback** — previous app is zipped before each install, `relios rollback` to restore
- **Dry-run** — `relios release --dry-run` builds and verifies with zero writes
- **Works with SwiftPM and Xcode** — two modes, same workflow

## Two modes

| Project type | Mode | What Relios does |
|---|---|---|
| **SwiftPM** | assembly | Builds binary, assembles `.app` from scratch, generates Info.plist, signs ad-hoc |
| **Xcode / XcodeGen** | passthrough | Runs `xcodebuild`, takes the complete `.app` as-is, installs it |

`relios init` auto-detects which mode to use:

- Found `Package.swift` (no Xcode markers) → **assembly**
- Found `.xcodeproj`, `.xcworkspace`, or `project.yml` → **passthrough**

## Installation

### Homebrew (recommended)

```bash
brew tap papa-channy/relios
brew install relios
```

### From source

```bash
git clone https://github.com/papa-channy/relios.git
cd relios
swift build -c release
cp .build/release/relios /usr/local/bin/relios
```

Verify: `relios --help`

## Commands

| Command | Description |
|---|---|
| `relios init` | Generate `relios.toml` + `AppVersion.swift` |
| `relios doctor` | Check release readiness |
| `relios release [patch\|minor\|major]` | Build, package, sign, install. No argument = build number only |
| `relios release --dry-run` | Build + verify without writing anything |
| `relios inspect` | Show the latest release manifest |
| `relios rollback [--to <zip>]` | Restore a previous app from backup |

### Release options

```
relios release [patch|minor|major]
  --dry-run          Build and verify only — zero writes
  --no-open          Skip auto-launch after install
  --install-path     Override [install].path
  --skip-backup      Skip backup of existing app
  --verbose          Show subprocess output
```

### Version bumping

| Argument | Version change | Build number |
|---|---|---|
| *(none)* | unchanged | +1 |
| `patch` | x.y.z → x.y.(z+1) | reset to 1 |
| `minor` | x.y.z → x.(y+1).0 | reset to 1 |
| `major` | x.y.z → (x+1).0.0 | reset to 1 |

---

## Passthrough mode details

Xcode projects already produce a complete `.app` via `xcodebuild`. Relios does **not** re-assemble the bundle — it handles version bumping, backup, install, and launch.

**What passthrough skips:**
- Bundle assembly (Xcode already built the `.app`)
- Info.plist generation (Xcode already wrote it)
- Ad-hoc signing by default (`signing.mode = "keep"` preserves Xcode's signature)

**Important:** `relios init` guesses the scheme name from the `.xcodeproj` filename. These are placeholders — verify before your first release:

```toml
[build]
# Verify -scheme matches your actual Xcode scheme.
# -derivedDataPath build pins output to a predictable location.
command = "xcodebuild -scheme MyApp -configuration Release -derivedDataPath build build"

[bundle]
# Must match where xcodebuild places the .app.
output_path = "build/Build/Products/Release/MyApp.app"
mode = "passthrough"

[signing]
# "keep" preserves Xcode's signature. Change to "adhoc" to re-sign.
mode = "keep"
```

If the scheme name is wrong, `relios release --dry-run` will fail at artifact verification — telling you the `.app` wasn't found.

## `relios.toml` schema

### SwiftPM project (assembly)

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

### Xcode project (passthrough)

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
mode = "keep"
```

### Key fields by mode

| Section | Field | Assembly | Passthrough | Notes |
|---|---|---|---|---|
| `[project]` | `type` | `swiftpm` | `xcodebuild` | Detected by `init` |
| `[build]` | `command` | `swift build -c release` | `xcodebuild ...` | Shell command Relios runs |
| `[build]` | `binary_path` | `.build/release/MyApp` | *(empty)* | Not used in passthrough |
| `[bundle]` | `mode` | `assembly` | `passthrough` | Controls .app handling |
| `[bundle]` | `output_path` | `dist/MyApp.app` | `build/Build/Products/Release/MyApp.app` | In passthrough: where xcodebuild places the .app |
| `[bundle]` | `plist_mode` | `generate` | *(ignored)* | Skipped in passthrough |
| `[signing]` | `mode` | `adhoc` | `keep` | `keep` preserves existing signature |

## Doctor checks

`relios doctor` runs 6 checks:

| Check | What it verifies |
|---|---|
| project type | Xcode markers + assembly mode → fails with guidance to use passthrough |
| spec validity | Required fields (name, bundle_id, binary_target) are non-empty |
| version source | `[version].source_file` exists and patterns match |
| build readiness | `swift` (SwiftPM) or `xcodebuild` (Xcode) is in PATH |
| install path | Parent directory of `[install].path` exists |
| signing readiness | `codesign` is in PATH (skipped when `signing.mode = "keep"`) |

## Release pipeline

### Assembly (SwiftPM)

1. Preflight validation (doctor rules, fail-fast)
2. Read current version from source file
3. Compute next version + build number
4. Run `swift build -c release`
5. Verify build binary exists
6. Update version source file *(dry-run stops here)*
7. Assemble `.app` bundle
8. Generate `Info.plist`
9. Ad-hoc sign
10. Back up existing app
11. Terminate running app
12. Install to target path
13. Launch app
14. Write release manifest

### Passthrough (Xcode)

1. Preflight validation (doctor rules, fail-fast)
2. Read current version from source file
3. Compute next version + build number
4. Run `xcodebuild`
5. Verify `.app` exists at `[bundle].output_path`
6. Update version source file *(dry-run stops here)*
7. ~~Assemble .app~~ *(skipped)*
8. ~~Generate Info.plist~~ *(skipped)*
9. Sign if `"adhoc"`, skip if `"keep"`
10. Back up existing app
11. Terminate running app
12. Install to target path
13. Launch app
14. Write release manifest

## Release manifest

Each release writes `dist/releases/latest.json` (overwritten) and `dist/releases/history/<timestamp>.json` (append-only).

```json
{
  "app_name": "MyApp",
  "bundle_id": "com.example.myapp",
  "version": "1.2.4",
  "build": "1",
  "bundle_path": "dist/MyApp.app",
  "install_path": "/Applications/MyApp.app",
  "signing_mode": "adhoc",
  "bundle_mode": "assembly",
  "launched_after_install": true,
  "timestamp": "2026-04-11T10:00:00Z"
}
```

## v1 scope

Relios v1 targets local development releases:

- **SwiftPM** projects: full assembly pipeline (build binary → .app → sign → install)
- **Xcode/XcodeGen** projects: passthrough pipeline (xcodebuild → take .app → install)
- Ad-hoc signing or keep existing signature
- No notarization, no Developer ID, no DMG packaging
- No App Store distribution

## Requirements

- macOS 13+
- Swift toolchain (Xcode Command Line Tools)
- One of:
  - SwiftPM project with at least one executable target (`Package.swift`)
  - Xcode project (`.xcodeproj`, `.xcworkspace`, or `project.yml`)

## Smoke test checklist

Run before each release of Relios itself.

### SwiftPM (assembly)

```bash
cd /path/to/any-swiftpm-project
relios init                    # creates relios.toml + AppVersion.swift
relios doctor                  # all 6 checks pass
relios release patch --dry-run # builds, verifies, zero writes
relios release patch           # full pipeline
relios inspect                 # shows manifest with bundle_mode = "assembly"
relios rollback                # restores previous app from backup
```

### Xcode (passthrough)

```bash
cd /path/to/any-xcode-project
relios init                    # detects .xcodeproj, generates passthrough config
# Edit relios.toml: verify [build].command scheme and [bundle].output_path
relios doctor                  # all 6 checks pass
relios release patch --dry-run # xcodebuild runs, .app verified, zero writes
relios release patch           # full pipeline
relios inspect                 # shows manifest with bundle_mode = "passthrough"
```

## License

MIT
