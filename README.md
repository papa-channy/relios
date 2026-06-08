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
| `relios doctor [--fix]` | Check release readiness (`--fix` applies safe automatic fixes) |
| `relios release [patch\|minor\|major]` | Build, package, sign, install. No argument = build number only |
| `relios release --dry-run` | Build + verify without writing anything |
| `relios build` | Compile + verify the artifact only — no version bump, no install |
| `relios install` | Install the already-built `.app` without rebuilding |
| `relios open` | Launch the currently installed app |
| `relios inspect` | Show the latest release manifest |
| `relios rollback [--to <zip>]` | Restore a previous app from backup |
| `relios version [--build\|--full]` | Print the current app version from the version source |
| `relios signing <status\|setup\|import\|verify>` | Inspect/configure Apple Developer ID signing |
| `relios dmg` | Package the current `.app` into a DMG |
| `relios notarize [path]` | Submit a zip/DMG to Apple notarization and staple the ticket |
| `relios update generate` | Write the auto-update feed (`update.json`) for the current version |
| `relios ci <init\|doctor>` | Scaffold/verify GitHub Actions release workflows |

### Release options

```
relios release [patch|minor|major]
  --dry-run          Build and verify only — zero writes
  --no-open          Skip auto-launch after install
  --install-path     Override [install].path
  --skip-backup      Skip backup of existing app
  --verbose          Show subprocess output
```

### Install / open options

```
relios install
  --install-path     Override [install].path
  --no-open          Skip auto-launch after install
  --skip-backup      Skip backup of existing app
  --verbose          Show subprocess output

relios open
  --install-path     Override [install].path
```

`install` takes the `.app` already sitting at `[bundle].output_path` (from a
prior `release` or build) and installs it — backup, terminate running app,
copy to `[install].path`, launch, and write the release manifest — without
rebuilding, bumping the version, or re-signing.

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
| `[build]` | `executable` + `arguments` | `"swift"` + `["build","-c","release"]` | `"xcodebuild"` + `[...]` | **Preferred** — runs without a shell |
| `[build]` | `command` | `swift build -c release` | `xcodebuild ...` | Legacy shell string; `doctor` warns unless `allow_shell = true` |
| `[build]` | `binary_path` | `.build/release/MyApp` | *(empty)* | Not used in passthrough |
| `[bundle]` | `mode` | `assembly` | `passthrough` | Controls .app handling |
| `[bundle]` | `output_path` | `dist/MyApp.app` | `build/Build/Products/Release/MyApp.app` | In passthrough: where xcodebuild places the .app |
| `[bundle]` | `plist_mode` | `generate` | *(ignored)* | Skipped in passthrough |
| `[signing]` | `mode` | `adhoc` | `keep` | `keep` preserves existing signature |

## Doctor checks

`relios doctor` runs 11 checks:

| Check | What it verifies |
|---|---|
| project type | Xcode markers + assembly mode → fails with guidance to use passthrough |
| spec validity | Required fields (name, bundle_id, binary_target) are non-empty |
| version source | `[version].source_file` exists and patterns match |
| build readiness | `swift` (SwiftPM) or `xcodebuild` (Xcode) is in PATH |
| install path | Parent directory of `[install].path` exists |
| signing readiness | `codesign` is in PATH; for `developer-id`, the identity exists in the keychain (skipped when `signing.mode = "keep"`) |
| dmg readiness | `dmgbuild` is available (skipped when `[dmg]` is absent/disabled) |
| notarize readiness | `notarytool` is available and credentials are set (skipped when `[notarize]` is absent/disabled) |
| update readiness | `[update].download_url_template` has the required placeholders (skipped when `[update]` is absent/disabled) |
| path safety | `[bundle].output_path` stays in the project; `[install].path` is a `.app`, not a protected location (`/`, `$HOME`, project root), and differs from `output_path` |
| build trust | warns when `[build].command` runs via a shell (arbitrary code); prefer `[build].executable` + `arguments`, or set `allow_shell = true` |

### `--fix`

`relios doctor --fix` applies safe, additive fixes before re-running the
checks. Fixes are idempotent and never destructive (they create missing
directories; they never delete or overwrite). Currently:

| Fix | Action |
|---|---|
| install path parent | Creates the missing parent directory of `[install].path` |

## Release pipeline

### Assembly (SwiftPM)

1. Preflight validation (doctor rules, fail-fast)
2. Read current version from source file
3. Compute next version + build number
4. Update version source file *(non-dry-run only; snapshotted)*
5. Run `swift build -c release` *(compiles the bumped version into the binary)*
6. Verify build binary exists *(dry-run stops here; on failure here or in build, the version source is restored)*
7. Assemble `.app` bundle
8. Generate `Info.plist`
9. Ad-hoc sign
10. Back up existing app
11. Terminate running app
12. Install to target path
13. Launch app
14. Write release manifest

> **Version is bumped before the build** so the compiled binary embeds the same version its `Info.plist`, manifest, DMG name, and tag declare. If the build or artifact check fails, the version source is restored to its pre-release contents. Dry-run never writes the version source — it builds the current source purely to verify the build succeeds.

### Passthrough (Xcode)

1. Preflight validation (doctor rules, fail-fast)
2. Read current version from source file
3. Compute next version + build number
4. Update version source file *(non-dry-run only; snapshotted)*
5. Run `xcodebuild` *(builds from the bumped source)*
6. Verify `.app` exists at `[bundle].output_path` *(dry-run stops here; on failure here or in build, the version source is restored)*
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

## Distribution

Beyond local installs, Relios handles signed, notarized, distributable builds.
These features are **opt-in** — add the relevant section to `relios.toml` to
enable them; omit it and the pipeline behaves exactly as the local flow above.

- **Developer ID signing** — `[signing].mode = "developer-id"` signs with your
  Developer ID identity (hardened runtime on by default, optional entitlements).
  Configure it interactively with `relios signing setup`.
- **DMG packaging** — `relios dmg` (or `[dmg]` in the spec) packages the `.app`
  into a distributable disk image via `dmgbuild`.
- **Apple notarization** — `relios notarize` submits a zip/DMG to Apple's Notary
  Service and staples the ticket. Credentials come from the environment
  (`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`) — never the TOML.
- **GitHub Actions** — `relios ci init` scaffolds a release workflow that wires
  build → sign → DMG → notarize → staple → publish, conditioned on which spec
  sections you've enabled.

### Developer ID signing (`[signing]`)

```toml
[signing]
mode = "developer-id"
identity = "Developer ID Application: Your Name (ABCDE12345)"
team_id = "ABCDE12345"
hardened_runtime = true        # default true; required for notarization
entitlements_path = ""         # optional --entitlements plist
```

### DMG (`[dmg]`)

```toml
[dmg]
enabled = true
output_dir = "dist"            # default "dist"
volume_name = ""               # default: app display name
background_color = "#FCF5F3"   # solid color (no background image)
window_size = [540, 360]       # [width, height]
icon_size = 80
```

### Notarization (`[notarize]`)

```toml
[notarize]
enabled = true
target = "auto"                # auto | dmg | zip (auto prefers DMG)
timeout_seconds = 3600         # max wait for notarytool --wait
```

> Credentials are read from the environment, not the TOML:
> `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` (app-specific, not your Apple ID
> password), and `APPLE_TEAM_ID`. This keeps `relios.toml` commit-safe.

## Auto-update feed

Publishing a release puts an artifact on GitHub — but an *already-installed*
app has no way to learn a newer version exists. The `[update]` feature closes
that loop: it generates a small JSON manifest (`update.json`) that your shipped
app polls to discover and download updates.

```toml
[update]
enabled = true
feed_file = "update.json"      # manifest filename (uploaded as a Release asset)
output_dir = "dist"            # where it's written locally
# How the artifact download URL is built when --download-url isn't passed.
# Placeholders: {repo} (owner/repo), {tag} (v2.0.1), {asset} (filename).
download_url_template = "https://github.com/{repo}/releases/download/{tag}/{asset}"
# Public URL your app's updater polls (informational — echoed by the CLI).
feed_url = "https://github.com/OWNER/REPO/releases/latest/download/update.json"
sign = true                    # Ed25519-sign the feed (see "Signed feed" below)
```

Generate the manifest locally or in CI:

```bash
relios update generate \
  --tag v2.0.1 \
  --repo OWNER/REPO \
  --asset MyApp-2.0.1.dmg \
  --artifact dist/MyApp-2.0.1.dmg   # local file → sha256 + size
  --commit "$GITHUB_SHA" \          # provenance
  --notes-file notes.txt            # or --notes "..."
# or pass an explicit --download-url to bypass the template
```

Produced `update.json`:

```json
{
  "app_name": "MyApp",
  "bundle_id": "com.example.myapp",
  "version": "2.0.1",
  "build": "7",
  "url": "https://github.com/OWNER/REPO/releases/download/v2.0.1/MyApp-2.0.1.dmg",
  "notes": "- Fixed a crash\n- Faster startup",
  "notes_url": "https://github.com/OWNER/REPO/releases/tag/v2.0.1",
  "min_macos": "14.0",
  "published_at": "2026-06-07T09:24:46Z",
  "sha256": "6ff1b92e9521ed2d…",
  "size": 12345678,
  "git_commit": "a1b2c3d…"
}
```

Your app fetches `feed_url`, compares `version`/`build` against its own, and —
if newer — verifies `sha256` after downloading `url`, then points the user at it
(`notes_url` is the full release page). Because GitHub resolves
`releases/latest/download/<file>` to the newest release, the URL stays stable.

### Signed feed (Ed25519)

A bare download URL trusts whoever controls the release asset. Signing the feed
means a hijacked asset isn't enough — the app rejects an update whose `update.json`
doesn't verify against your public key.

```bash
relios update keygen                 # writes .relios/relios-update.key, prints the public key
# Embed the printed public key in your app. Store the private key as a CI secret:
#   gh secret set RELIOS_UPDATE_SIGNING_KEY < .relios/relios-update.key
```

With `[update].sign = true` and `RELIOS_UPDATE_SIGNING_KEY` set (or
`--signing-key-file`), `relios update generate` writes `update.json.sig` next to
the feed. The generated `release.yml` uploads it and reads the key from the
secret. App-side verification (Swift Crypto):

```swift
import Crypto
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: EMBEDDED_PUBKEY)!)
let ok = key.isValidSignature(Data(base64Encoded: sigFileContents)!, for: updateJSONBytes)
// only trust update.json (and its url/sha256) when ok == true
```

### Push-to-release automation

When `[update].enabled`, `relios ci init` also generates
`.github/workflows/auto-release.yml`. On every push to `main` it reads the app
version (`relios version`) and, **only if the version changed** (no `v<version>`
tag exists yet), tags it — which triggers `release.yml` to build, sign, package,
notarize, publish, and upload a fresh `update.json`. Ordinary commits that don't
change the version are a no-op.

So the full loop becomes: bump the version in your source file → push to `main`
→ users get the update. Release notes for the feed are generated automatically
from `git log` between the previous tag and the new one.

The generated workflows are hardened: least‑privilege top‑level `permissions`
(`contents: read`) with per‑job escalation, a `concurrency` guard, and a
**tag == AppVersion** verification step that fails the release on mismatch.

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
relios install                 # re-installs the built .app without rebuilding
relios open                    # launches the installed app
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
