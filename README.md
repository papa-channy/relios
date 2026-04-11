# Relios

Local release pipeline for SwiftPM-based macOS apps.

One command to build, package, sign, and install your app locally.

```
relios release patch
```

## What it does

Relios replaces manual release scripts with a declarative `relios.toml` spec:

- **Build** your SwiftPM project in release mode
- **Bump** version (patch/minor/major) or just the build number
- **Assemble** a `.app` bundle with Info.plist
- **Sign** ad-hoc (`codesign --force --sign -`)
- **Back up** the currently installed app (zip rotation)
- **Install** to `/Applications` (or any path)
- **Launch** the app after install

All steps are atomic: build succeeds before version source is touched, backup happens before install, and `--dry-run` guarantees zero writes.

## Quick start

```bash
# In your SwiftPM project root
relios init
relios doctor
relios release patch
```

`init` generates two files:
- `relios.toml` — release spec (edit `bundle_id` and `icon_path` before first real release)
- `AppVersion.swift` — version source with `static let current = "0.1.0"` and `static let build = "1"`

## Commands

| Command | Description |
|---|---|
| `relios init` | Generate `relios.toml` + `AppVersion.swift` skeleton |
| `relios doctor` | Check release readiness (spec, version source, toolchain, paths) |
| `relios release [patch\|minor\|major]` | Build, package, sign, install. No argument = build number only |
| `relios release --dry-run` | Run build + verify without writing anything |
| `relios inspect` | Show the latest release manifest |
| `relios rollback [--to <zip>]` | Restore the previous app from backup |

### Release options

```
relios release [patch|minor|major]
  --dry-run          Build and verify only — zero writes
  --no-open          Skip auto-launch after install
  --install-path     Override [install].path
  --skip-backup      Skip backup of existing app
  --verbose          Show subprocess output
```

## `relios.toml` schema

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

[install]
path = "/Applications/MyApp.app"
auto_open = true
backup_dir = "dist/app-backups"
keep_backups = 3
quit_running_app = true

[signing]
mode = "adhoc"
```

## Doctor checks

`relios doctor` runs 5 checks:

| Check | What it verifies |
|---|---|
| spec validity | Required fields (name, bundle_id, binary_target) are non-empty |
| version source | `[version].source_file` exists and patterns match |
| build readiness | `swift` is in PATH |
| install path | Parent directory of `[install].path` exists |
| signing readiness | `codesign` is in PATH |

## Release pipeline steps

1. Preflight validation (doctor rules, fail-fast)
2. Read current version from source file
3. Compute next version + build number
4. Run build command
5. Verify build artifact exists
6. Update version source file *(skipped in dry-run)*
7. Assemble `.app` bundle *(skipped in dry-run)*
8. Generate `Info.plist` *(skipped in dry-run)*
9. Ad-hoc sign *(skipped in dry-run)*
10. Back up existing app *(skipped in dry-run)*
11. Terminate running app *(skipped in dry-run)*
12. Install to target path *(skipped in dry-run)*
13. Launch app *(skipped in dry-run)*
14. Write release manifest *(skipped in dry-run)*

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
  "launched_after_install": true,
  "timestamp": "2026-04-11T10:00:00Z"
}
```

## Version bumping

| Argument | Version change | Build number |
|---|---|---|
| *(none)* | unchanged | +1 |
| `patch` | x.y.z → x.y.(z+1) | reset to 1 |
| `minor` | x.y.z → x.(y+1).0 | reset to 1 |
| `major` | x.y.z → (x+1).0.0 | reset to 1 |

## v1 scope

Relios v1 targets local development releases:
- SwiftPM projects only
- Ad-hoc signing only
- `.app` bundles assembled directly (no xcodebuild)
- No notarization, no Developer ID, no DMG packaging

## Requirements

- macOS 13+
- Swift toolchain (Xcode Command Line Tools)
- SwiftPM-based project with at least one executable target

## Building from source

```bash
git clone <repo-url>
cd relios
swift build -c release
# Binary at .build/release/relios
```

## License

MIT
