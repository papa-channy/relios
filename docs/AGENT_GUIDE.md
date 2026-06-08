# Relios Agent Guidebook

**Audience:** an autonomous AI coding agent operating a shell in a *target* project (not the Relios repo itself), tasked with adopting and operating Relios end‑to‑end on the user's behalf.

**Goal of this guide:** let you (the agent) translate a high‑level human goal — *"ship my macOS app,"* *"set up CI,"* *"make updates automatic,"* *"reinstall the latest build"* — into the correct sequence of `relios` commands, assess impact **before** committing changes, recover from failures autonomously, and stop for the human only when something is genuinely irreversible or requires a secret.

This guide is self‑contained. If you have only this file and the `relios` binary, you can succeed.

---

## Table of contents

1. [Golden rules (read first)](#1-golden-rules-read-first)
2. [The output contract — how to read every command](#2-the-output-contract)
2b. [Structured output (`--format json`) — preferred for agents](#2b-structured-output---format-json--preferred-for-agents)
3. [Mental model: what Relios is and what it owns](#3-mental-model)
4. [The Assess → Proceed → Fix loop](#4-the-assess--proceed--fix-loop)
5. [`--dry-run` and its impact‑assessment substitutes](#5-dry-run-and-substitutes)
6. [Command reference for agents](#6-command-reference-for-agents)
7. [The `relios.toml` schema (every field)](#7-the-reliostoml-schema)
8. [Playbooks (goal → exact command sequence)](#8-playbooks)
9. [Decision trees](#9-decision-trees)
10. [Failure → remediation matrix](#10-failure--remediation-matrix)
11. [Reversibility ladder & when to stop for the human](#11-reversibility-ladder)
12. [Secrets & environment variables](#12-secrets--environment-variables)
13. [Files Relios creates (so you never clobber blindly)](#13-files-relios-creates)
14. [Quick reference appendix](#14-quick-reference-appendix)

---

## 1. Golden rules (read first)

1. **Assess before you mutate.** Every task begins read‑only. The universal probe is `relios doctor` (never writes, except `--fix`). For releases, add `relios release <bump> --dry-run` (builds + verifies, makes **zero Relios‑owned writes**).
2. **Treat the `Fix:` line as an instruction to yourself.** Every failure prints `Reason:` + `Fix:`. The `Fix:` text is machine‑actionable; apply it, then re‑assess. Section 10 maps the common ones to concrete automated actions.
3. **`relios build` compiles and verifies, without bump/install.** It runs `[build].command`, verifies the artifact/.app exists, and makes **zero** Relios‑owned writes (no version bump, no bundle, no install). Exit 0 on success, nonzero on failure. Use it to compile‑check; use `relios release --dry-run` when you also want preflight validation, or `relios release <bump>` to actually produce/install a build.
4. **`--dry-run` exists only on `relios release`.** For all other mutating commands use the substitutes in [Section 5](#5-dry-run-and-substitutes).
5. **Never re‑run `relios init` on a configured project without backing up `relios.toml` first.** `init` *overwrites* `relios.toml` (it preserves an existing `AppVersion.swift`, but not the spec). See [Section 6.1](#61-relios-init).
6. **Irreversible actions need a hard gate.** Pushing a git tag, publishing a GitHub Release, and Apple notarization submission are not cheaply reversible. Gate them behind a green `doctor` + (for releases) a clean `--dry-run`, and for anything that consumes secrets or publishes outward, confirm with the human unless they durably authorized it. See [Section 11](#11-reversibility-ladder).
7. **Prefer the backup‑preserving defaults.** `relios release` and `relios install` back up the currently installed app before replacing it. Do **not** pass `--skip-backup` unless the human asked — the backup is what makes `relios rollback` possible.
8. **Exit code is truth, but parse the text too.** A nonzero exit means failure for every command. `doctor` exits nonzero only when at least one check is `[fail]` (a `[warn]` is exit 0).
9. **Idempotency varies by command.** Know which commands are safe to repeat (`doctor`, `version`, `inspect`, `signing status`, `release --dry-run`) and which mutate (`init`, `release`, `install`, `signing setup`, `ci init`, `update generate`, `rollback`). Section 6 marks each.
10. **You are operating in the target project's working directory.** All commands read `./relios.toml` and resolve paths relative to the current directory. `cd` into the project root first.

---

## 2. The output contract

Relios commands speak a consistent, parseable dialect. Learn it once.

### Success
Each completed step prints a line beginning with `✓`:
```
✓ Version: 1.2.3 (build 4) → 1.2.4 (build 1)
✓ Build completed
✓ Installed to /Applications/MyApp.app
```
A trailing summary block (indented `  Key: value`) may follow.

### Failure
Mutating commands that fail print a three‑line block and exit nonzero:
```
[<command>] failed[ at: <step>]
  Reason: <what went wrong>
  Fix: <what to do about it>
```
- `<command>` is the command or stage name (`release`, `install`, `dmg`, `notarize`, `ci init`, `spec load`, …).
- `at: <step>` appears for `release` (the pipeline step that failed — see [Section 6.3](#63-relios-release)).
- With `--verbose`, `release` also appends a `--- stderr (tail) ---` block from the failed subprocess (e.g. compiler errors). **Always re‑run a failed `release` with `--verbose` to see compiler output before remediating.**

### `doctor` output
```
[ok]   <title>
[warn] <title>
  Reason: ...
  Fix: ...
[fail] <title>
  Reason: ...
  Fix: ...

Status: ready | mostly ready | not ready
```
- `ready` = all `[ok]`. `mostly ready` = some `[warn]`, no `[fail]`. `not ready` = at least one `[fail]`.
- **Exit code:** nonzero iff any `[fail]`. A `[warn]` does not fail the command — but you should still evaluate whether it blocks the human's actual goal (e.g. a `dmgbuild not found` warn *does* block `relios dmg`).

### Parsing recipe (pseudo)
```
run command; capture stdout+stderr+exit
if exit == 0 and no "] failed" line:  treat as success; scrape ✓ lines + summary
else: extract Reason: and Fix: lines → consult Section 10 → remediate → re-assess
```

---

## 2b. Structured output (`--format json`) — preferred for agents

Every leaf command accepts **`--format json`** (or set `RELIOS_FORMAT=json` once). In JSON mode the command writes **exactly one JSON object to stdout** — success *or* error — so you always parse the same stream; progress chatter goes to stderr. **Branch on the stable `id`, never on English `reason`/`fix` text.**

### Bootstrap handshake — call this first
```bash
relios capabilities --format json
```
Returns `cli_version`, the output `schema_version` (currently **1**), and per-command flags (`implemented`, `dry_run`, `mutating`). Confirm `schema_version` matches what this guide documents before issuing mutating commands; if it differs, don't infer behavior — re-read `relios <cmd> --help`.

### Envelope
```jsonc
{
  "schema_version": 1,
  "command": "doctor",
  "status": "ready" | "not_ready" | "ok" | "fail",
  "exit_code": 0,          // mirrors the process exit
  // exactly ONE of:
  "data":   { ... },        // success payload (release/install/build/inspect/version/…)
  "checks": [ <check> ],    // doctor, ci doctor
  "error":  <error>         // any failure
}
```

### Error / check object — the actionable part
```jsonc
{
  "id": "SIGNING_IDENTITY_NOT_FOUND",   // stable; switch on this
  "severity": "fail" | "warn" | "ok",
  "reason": "…", "fix": "…",            // human strings (do not parse)
  "requires_human": true,               // false ⇒ you can self-remediate
  "remediation": {                      // structured next step
    "kind": "run_command",              // run_command | edit_config | set_env | install_tool | none
    "command": ["relios","signing","import","<path-to.p12>"],
    "required_inputs": ["path-to.p12"]  // placeholders you must fill
  },
  "step": "preflight validation",        // release errors only
  "detail": "…"                          // stderr tail when --verbose
}
```

### Agent decision rule
```
run with --format json
parse stdout as one JSON object
if status in {ok, ready}:        use .data / .checks, proceed
else (fail / not_ready):
   for the .error (or each failing .checks[]):
     if requires_human:          STOP, report id + reason + required_inputs
     else apply .remediation:
        run_command  → run it (fill required_inputs)
        edit_config  → patch the named relios.toml keys
        install_tool → run the install command
        set_env      → ensure the named env vars are set
   re-run and re-evaluate
```

`requires_human: true` means an agent cannot synthesize the input (an Apple password, a `.p12`, a signing-identity choice). `false` means a deterministic fix exists. Treat every doctor `checks[]` entry the same way, scoped to your goal (a `warn` you don't need for the current goal is informational).

## 3. Mental model

### What Relios is
A local release pipeline for macOS apps. One spec file (`relios.toml`) drives: version bump → build → assemble/verify `.app` → sign → backup → install → launch → manifest, plus optional distribution (DMG, Developer ID signing, Apple notarization), CI scaffolding, and an auto‑update feed.

### Two modes (auto‑detected by `init`)
| Project marker | `[project].type` | `[bundle].mode` | What Relios does |
|---|---|---|---|
| `Package.swift` only | `swiftpm` | `assembly` | Builds the binary, **assembles** the `.app` from scratch, generates `Info.plist`, signs. |
| `.xcodeproj` / `.xcworkspace` / `project.yml` | `xcodebuild` | `passthrough` | Runs your `xcodebuild` command, takes the finished `.app` **as‑is**, installs it. Skips assembly + plist generation. |

**Consequence for you:** in passthrough mode the `[build].command` scheme name and `[bundle].output_path` are *guesses* from the filename and must be verified before the first release. A wrong scheme/path surfaces as a `verify build artifact` failure in `--dry-run`.

### What Relios *owns* (writes) — never assume these are yours to hand‑edit casually
- `relios.toml` — the spec (you may patch it; `signing setup` patches it surgically).
- `AppVersion.swift` (or the configured `[version].source_file`) — version + build are rewritten on release.
- `dist/<App>.app` — the assembled/copied bundle (`[bundle].output_path`).
- `dist/<App>-<version>.dmg` — DMG output (when `[dmg]`).
- `dist/update.json` — the update feed (when `[update]`).
- `dist/app-backups/*.zip` — rotating backups of the installed app.
- `dist/releases/latest.json` + `dist/releases/history/<ts>.json` — release manifests.
- `.github/workflows/{release,ci,auto-release}.yml` — CI (when `ci init`).
- The install target, default `/Applications/<App>.app`.

### The version source
`[version]` declares a `source_file` plus two regexes (`version_pattern`, `build_pattern`), each with one capture group. Relios reads and rewrites the captured substrings. The canonical file:
```swift
enum AppVersion {
    static let current = "1.2.3"
    static let build = "4"
}
```
This is the single source of truth that drives bumps, tags, manifests, and the update feed.

---

## 4. The Assess → Proceed → Fix loop

This is the core operating procedure the human asked for. Apply it to **every** non‑trivial task.

```
┌─────────────────────────────────────────────────────────────┐
│ 1. ASSESS (read-only)                                        │
│    • cd into project root                                     │
│    • relios doctor                  ← config & tooling        │
│    • (for release) relios release <bump> --dry-run           │
│      → builds + verifies, ZERO Relios writes                 │
│    • read the ✓/[ok]/[warn]/[fail] + Reason/Fix              │
├─────────────────────────────────────────────────────────────┤
│ 2. DECIDE                                                    │
│    • all green & dry-run clean → PROCEED                     │
│    • any [fail] / dry-run failure → FIX (go to 3)           │
│    • [warn] that blocks the goal → FIX; else note & proceed  │
│    • irreversible step ahead (tag/publish/notarize) → gate   │
│      (Section 11) before proceeding                          │
├─────────────────────────────────────────────────────────────┤
│ 3. FIX                                                       │
│    • map Reason/Fix → Section 10 remediation                 │
│    • apply the smallest change (edit relios.toml, install a  │
│      tool, set an env var, correct a path/scheme)            │
│    • re-ASSESS (back to 1). Never proceed on a red signal.   │
├─────────────────────────────────────────────────────────────┤
│ 4. PROCEED (mutate)                                         │
│    • run the real command (drop --dry-run)                   │
├─────────────────────────────────────────────────────────────┤
│ 5. VERIFY (read-only)                                        │
│    • relios inspect          ← manifest reflects the release │
│    • relios doctor           ← still green                   │
│    • signing verify / file existence as relevant            │
└─────────────────────────────────────────────────────────────┘
```

**Why this is maximally efficient:** the expensive, fallible part of a release is the *build*. `--dry-run` runs exactly that (build + artifact check) while guaranteeing nothing is written, signed, installed, or published. Note the real release **builds again** — the bumped version source must be compiled in (see [Section 6.3](#63-relios-release)); build caches usually make the second build fast, but do **not** assume the dry‑run artifact is reused. The payoff is that you learn of any preflight/build failure with zero cleanup, fix it, and only then commit to a run that mutates state — you never leave a half‑applied release behind.

---

## 5. `--dry-run` and substitutes

### What `relios release --dry-run` actually does
**Runs (in order):** preflight rules → read current version → compute next version → **execute the build command** → verify the build artifact / `.app` exists. Then **stops**.

**Preflight rules executed by dry‑run:** `XcodeProjectGuard`, `SpecValidity`, `VersionSource`, `BuildReadiness`, `SigningReadiness`. (So a missing/!keychain Developer ID identity **does** fail dry‑run.)

**Does NOT do:** update the version source, assemble the bundle, write `Info.plist`, sign, back up, install, launch, write the manifest.

**Coverage boundary — important:** dry‑run does **not** evaluate `DMGReadiness`, `NotarizeReadiness`, or `UpdateReadiness`, and it does not actually sign/notarize. For those, you must run **`relios doctor`** (which runs all 9 checks). So the complete pre‑flight for a distributable release is: `relios doctor` **and** `relios release <bump> --dry-run`, both green.

**Side effects to expect — `--dry-run` is NOT a filesystem no‑op.** It makes zero *Relios‑owned* writes (version source, bundle, install, backup, manifest). But the configured `[build].command` actually executes, so the compiler writes to `.build/`/DerivedData, and **any SwiftPM plugins or Xcode Run Script phases run and may modify generated or even tracked files**. Treat `[build].command` and the project's build scripts as code you are about to execute — inspect them first in an unfamiliar/untrusted repo, and never run a build that carries secrets on an untrusted branch/fork. To detect unexpected changes, bracket the probe (diff, don't just check "clean" — the tree may already be dirty):
```bash
git status --short > /tmp/relios-pre.txt
relios release <bump> --dry-run
git status --short > /tmp/relios-post.txt
diff /tmp/relios-pre.txt /tmp/relios-post.txt
```

**Clean dry‑run output looks like:**
```
✓ Preflight passed
✓ Version: 1.2.3 (build 4) → 1.2.4 (build 1)
✓ Build completed
✓ Verified build artifact        (or "✓ Verified .app exists" in passthrough)

Dry run — no files were written.
```

### Impact‑assessment substitutes for commands without `--dry-run`
Only `release` has `--dry-run`. Use these read‑only or non‑destructive probes for the rest:

| Command | How to assess impact safely first |
|---|---|
| `init` | `ls relios.toml` first. If it exists, **do not** run `init` (it overwrites). Patch the file instead, or back it up (`cp relios.toml relios.toml.bak`) and diff after. |
| `install` | `relios doctor` (config) + confirm a built `.app` exists at `[bundle].output_path`. Install backs up first, so it is reversible via `rollback`. |
| `open` | Inherently safe (launches an app). Confirm the install path exists first; `open` reports clearly if not. |
| `dmg` | `relios doctor` → `dmg readiness`. Confirm `[bundle].output_path` exists (you need a real prior `release`/build; `--dry-run` leaves no `.app`). Writing a DMG is additive (overwrites only stale DMGs in the output dir). |
| `notarize` | **Highest‑cost probe.** `relios doctor` → `notarize ready`; then `relios signing verify <artifact>` to confirm the signature is valid *before* submitting. Submission is a network op (minutes) and consumes an Apple quota — never submit on a red signal. |
| `signing setup` | `relios signing status` (read‑only) to see available identities + current spec. Then run `setup` with explicit `--identity`/`--team-id` (avoid the interactive prompt — you can't answer it). Patches only the `[signing]` block. |
| `signing import` | Idempotent‑ish (re‑importing is harmless). Requires the password env var; safe to run. |
| `update generate` | Writes one file. To preview without touching `dist/`, pass `--output /tmp/update.preview.json`, inspect, then run for real. |
| `ci init` | **Self‑gating:** without `--force` it *refuses* to overwrite existing workflow files and lists them. Run it once; if it errors `workflowExists`, inspect the existing files and only re‑run with `--force` if the human wants them regenerated. |
| `rollback` | Read the backup list first: `ls dist/app-backups`. Rollback restores the chosen/latest zip; the current app is replaced (also recoverable from a more recent backup). |

---

## 6. Command reference for agents

For each command: **purpose · when to choose it · syntax · writes? · idempotent? · preconditions · success/failure signals · recovery.**

### 6.1 `relios init`
- **Purpose:** generate a `relios.toml` skeleton (and `AppVersion.swift` if absent) by scanning the project; auto‑detects mode and a single Developer ID identity from the keychain.
- **Choose when:** the project has no `relios.toml` yet.
- **Syntax:** `relios init` (no flags).
- **Writes:** `relios.toml` (**OVERWRITES if present**); `AppVersion.swift` (only if it does **not** already exist).
- **Idempotent:** ⚠️ No — it overwrites `relios.toml`. Guard with `ls relios.toml` first.
- **Preconditions:** run from a project root containing `Package.swift` **or** `.xcodeproj`/`.xcworkspace`/`project.yml`.
- **Success:** prints `✓ Initialized Relios`, the created files, a `Detected:` block (project type, binary target, signing), and a `Review before first release:` block. Always read the `Review` block — in passthrough mode it tells you the scheme/output_path were guessed.
- **Failure:** `[init] failed` with `notSwiftPMProject` (not a recognized project) or `writeFailed` (permissions).
- **After init, always:** open `relios.toml`, fix `[app].bundle_id` (defaults to `com.example.<name>`), and in passthrough mode verify `[build].command` scheme + `[bundle].output_path`. Then `relios doctor`.

### 6.2 `relios doctor`
- **Purpose:** the universal pre‑flight. 9 read‑only checks across config and tooling.
- **Choose when:** before *every* mutating operation, and to verify after.
- **Syntax:** `relios doctor [--fix] [-v|--verbose]`.
- **Writes:** none — **except** `--fix`, which applies safe additive fixes (currently: create the missing parent directory of `[install].path`), prints `[fixed]`/`[fail]`, then re‑runs the checks.
- **Idempotent:** yes (and `--fix` is idempotent — it no‑ops when nothing needs fixing).
- **The 9 checks** (title → meaning; F=can fail/blocking, W=warn/non‑blocking):
  1. `project type` (F) — Xcode markers + assembly mode mismatch → use passthrough.
  2. `spec valid` (F) — `app.name`, `bundle_id`, `binary_target` non‑empty.
  3. `version source` (F) — `[version].source_file` exists and both patterns match.
  4. `build tool` (F) — `swift` (swiftpm) or `xcodebuild` (xcodebuild) on PATH.
  5. `install path` (W) — parent dir of `[install].path` exists (auto‑fixable with `--fix`).
  6. `signing readiness` (F for developer‑id) — `codesign` present; for `developer-id`, identity+team_id set and identity in keychain. Skipped for `keep`.
  7. `dmg readiness` (W) — `dmgbuild` on PATH (only when `[dmg]` enabled).
  8. `notarize readiness` (F/W) — `[notarize]` requires `developer-id` (F) and `notarytool` (F); missing env creds = W (CI supplies them).
  9. `update readiness` (W) — `[update].download_url_template` contains `{tag}` and `{asset}`.
- **Use the result:** `not ready` → fix the `[fail]`s before proceeding. `mostly ready` → decide per‑warn whether it blocks the goal (e.g. `dmgbuild not found` blocks `relios dmg` even though doctor exits 0).

### 6.3 `relios release`
- **Purpose:** the whole pipeline — build, bump, assemble/verify, sign, backup, install, launch, manifest.
- **Choose when:** the human wants to produce and install a build (the default action), or to cut a release.
- **Syntax:** `relios release [patch|minor|major] [--dry-run] [--no-open] [--install-path <p>] [--skip-backup] [-v|--verbose]`.
  - bump arg omitted → version unchanged, **build number +1**.
  - `patch|minor|major` → bump semver, **build resets to 1**.
- **Writes:** version source, `dist/<App>.app`, install target, backup zip, manifests. (`--dry-run`: none.)
- **Idempotent:** no (each run bumps + installs). `--dry-run` is idempotent.
- **Preconditions:** green‑enough `doctor`; for passthrough, correct scheme/output_path.
- **Pipeline order (real run):** preflight validation → read current version → compute next version → **update version source** → **build** → verify build artifact → assemble app bundle → write Info.plist → sign → backup existing app → terminate running app → install app → launch app → write release manifest. (Passthrough skips assemble + Info.plist.)
  - **The version is bumped *before* the build**, so the compiled binary embeds the same version that Info.plist, the manifest, the DMG name, and the git tag declare. The original source is snapshotted and **restored automatically if the build or artifact‑verify fails** — a failed release never leaves the version advanced. (This is the fix for the otherwise classic "binary is one version behind its label" bug.)
  - **Dry‑run subset:** preflight → read → compute → build (of the *current*, un‑bumped source) → verify. It writes nothing; the un‑bumped build is purely a viability probe and is discarded. The real run rebuilds with the bumped source.
  - The `failed at: <step>` label names the failing step; the most common are `build` (compile error → re‑run with `--verbose`) and `verify build artifact` (wrong `binary_path`/`output_path`/scheme).
- **Success:** a sequence of `✓` lines and a `Bundle/Install/Backup` summary.
- **Failure:** `[release] failed at: <step>` + Reason/Fix. **Re‑run with `--verbose`** to get the `--- stderr (tail) ---` (compiler/codesign output). The most common are at `build` (compile error → fix code) and `verify build artifact` (wrong `binary_path`/`output_path`/scheme).
- **Recovery:** a failed release before the install step leaves the previous install untouched. If install/launch already happened and the build is bad, `relios rollback`.

### 6.4 `relios install`
- **Purpose:** install the **already‑built** `.app` at `[bundle].output_path` without rebuilding, bumping, or re‑signing.
- **Choose when:** you already produced a good `.app` (e.g. a prior `release`, or an external build) and just need it installed; or to re‑install after a `rollback`.
- **Syntax:** `relios install [--install-path <p>] [--no-open] [--skip-backup] [-v|--verbose]`.
- **Writes:** install target, backup zip, manifest.
- **Preconditions:** a `.app` exists at `[bundle].output_path`; version source readable (used for backup naming + manifest).
- **Failure:** `appNotFound` (nothing built — run `release` first), `versionReadFailed` (fix `[version]` patterns).
- **Reversible:** yes (backs up first → `rollback`).

### 6.5 `relios open`
- **Purpose:** launch the currently installed app.
- **Syntax:** `relios open [--install-path <p>]`.
- **Writes:** none. **Idempotent:** yes.
- **Failure:** "No installed app at <path>" → run `release`/`install` first.

### 6.6 `relios inspect`
- **Purpose:** print the latest release manifest (app, version/build, bundle/install/backup paths, mode, signing, launched, timestamp).
- **Choose when:** verifying what was last released/installed.
- **Syntax:** `relios inspect`. **Writes:** none.
- **Failure:** "No release manifest found" → nothing has been released yet.

### 6.7 `relios rollback`
- **Purpose:** restore a previous app from a backup zip.
- **Syntax:** `relios rollback [--to <zip>] [--no-open] [-v|--verbose]`. Default restores the latest backup in `[install].backup_dir`.
- **Writes:** replaces the install target.
- **Preconditions:** at least one backup exists (`ls dist/app-backups`).
- **Failure:** `noBackupsFound` / `backupNotFound`.

### 6.8 `relios version`
- **Purpose:** print the **app** version from the version source (distinct from `relios --version`, which is the tool's version). Scriptable.
- **Syntax:** `relios version` → `2.0.1`; `--build` → `7`; `--full` → `2.0.1 (build 7)`.
- **Writes:** none. **Idempotent:** yes. Errors go to **stderr**; the value goes to **stdout** (so `V=$(relios version)` is clean).
- **Choose when:** you need the current version programmatically (the generated `auto-release.yml` uses it; you can too, e.g. to compute a tag).

### 6.9 `relios signing <sub>`
- **`status`** — read‑only: lists keychain codesigning identities + the current `[signing]` block + warns if the spec's identity is missing from the keychain. **Always run this before `setup`.**
- **`setup`** — patch `[signing]` to `developer-id`. Syntax: `relios signing setup [--identity "<name>"] [--team-id <TEAMID>] [--hardened-runtime] [--entitlements <plist>] [--non-interactive]`.
  - **Agent rule:** always pass `--identity` (and `--team-id` if not embedded in the identity string), or `--non-interactive`. Without `--identity` and not non‑interactive, it prompts on stdin (you can't answer). With `--non-interactive` and no `--identity` it fails fast with a clear message — preferable to hanging.
  - Patches only the `[signing]` block; preserves the rest of `relios.toml`.
- **`import`** — `relios signing import <path.p12> [--keychain <name>] [--password-env <VAR>]`. Reads the `.p12` password from env (default `RELIOS_CERT_PASSWORD`). Fails clearly if the env var is unset/empty.
- **`verify`** — `relios signing verify [<appPath>]`. Runs `codesign --verify` (+ details); defaults to `[bundle].output_path`. Exit nonzero if the signature is invalid. **Use this as the gate before `notarize`.**

### 6.10 `relios dmg`
- **Purpose:** package the current `.app` into a DMG via `dmgbuild`.
- **Syntax:** `relios dmg [-v|--verbose]`.
- **Preconditions:** `dmgbuild` on PATH (`pip install dmgbuild`); a built `.app` at `[bundle].output_path`. `[dmg]` controls naming/appearance.
- **Note:** you need a *real* prior `release` (or external build) — `--dry-run` does not leave a `.app` behind. Output: `dist/<App>-<version>.dmg` (or `<App>.dmg` if the version can't be read).
- **Failure:** `[dmg] failed` (missing `dmgbuild`, missing `.app`, write error).

### 6.11 `relios notarize`
- **Purpose:** submit a zip/DMG to Apple, wait, and staple the ticket.
- **Syntax:** `relios notarize [<path>] [--timeout <seconds>]`. Path omitted → resolved from `[notarize].target` (`auto` prefers DMG when `[dmg]` is enabled, else a zip).
- ⚠️ **The `zip` target expects `<App>-<version>.zip` at the project root and errors if it's absent. `relios release` does NOT create that zip — it is produced by the CI `release.yml` (a `ditto` step).** For **local** notarization, enable `[dmg]` and notarize the DMG (`target = "auto"`/`"dmg"`), or pass an explicit `<path>` to a zip/DMG you created.
- **Preconditions (all required):** `[notarize].enabled`; `[signing].mode = "developer-id"`; env `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`; a **validly signed** artifact. It also fails fast if `[signing].team_id` ≠ `APPLE_TEAM_ID`.
- **Cost/irreversibility:** network op, typically 2–15 min (can exceed an hour); consumes an Apple submission. **Gate hard** (Section 11): green `doctor`, `signing verify` passes, secrets present.
- **Failure:** `[notarize] failed` with the specific reason (disabled, missing creds, team mismatch, Apple "invalid"/"rejected").

### 6.12 `relios update generate`
- **Purpose:** write the auto‑update feed (`update.json`) for the current version.
- **Syntax:** `relios update generate --tag <vX.Y.Z> [--repo <owner/repo>] [--asset <file>] [--download-url <url>] [--notes <text>] [--notes-file <path>] [--notes-url <url>] [--output <path>]`.
  - URL resolution: explicit `--download-url` wins; otherwise the `[update].download_url_template` is filled with `{repo}`, `{tag}`, `{asset}` (so `--repo` + `--asset` are required in that case).
  - Notes: `--notes-file` (preferred for multiline / CI `git log`) or `--notes`. ⚠️ Avoid `--notes "- text…"` whose value starts with `-` — the arg parser rejects a value beginning with a dash. Use `--notes-file`.
  - `notes_url` is derived as the GitHub release page from `--repo`+`--tag` unless `--notes-url` is given.
- **Preconditions:** `[update].enabled`.
- **Writes:** `[update].output_dir/[update].feed_file` (default `dist/update.json`), or `--output`.
- **Preview safely:** `--output /tmp/update.preview.json`.

### 6.13 `relios ci <sub>`
- **`init`** — `relios ci init [--force]`. Generates `.github/workflows/release.yml` + `ci.yml`, plus `auto-release.yml` **when `[update].enabled`**. Conditionally injects keychain/DMG/notarize/update steps based on which spec sections are enabled.
  - **Self‑gating:** without `--force`, refuses to overwrite existing workflow files and lists them (`workflowExists`). This is your impact probe — inspect the listed files, then re‑run with `--force` only if regeneration is intended.
- **`doctor`** — `relios ci doctor`. 3 checks: release workflow present, ci workflow present, a `github.com` remote exists. Warns (not fails) when missing.

### 6.14 `relios build`
- **Purpose:** run `[build].command` and verify the artifact/.app exists — a compile‑check with no side effects on Relios‑owned state.
- **Choose when:** you want to confirm the project compiles without bumping the version, assembling a bundle, signing, or installing.
- **Syntax:** `relios build [-v|--verbose]`.
- **Writes:** none (only the build's own caches). **Idempotent:** yes.
- **Success:** `✓ Build completed` / `✓ Verified build artifact` (or `✓ Verified .app exists` in passthrough) + the artifact path.
- **Failure:** `[build] failed` + Reason/Fix (+ `--verbose` stderr tail); exit nonzero. Common: compile error, or wrong `binary_path`/scheme/`output_path`.
- **vs `release --dry-run`:** `build` is lighter (no preflight rules, no version compute); `--dry-run` additionally runs preflight validation (spec/version/signing readiness) and reports the next version. Use `--dry-run` as the pre‑release gate, `build` as a quick compile‑check.

---

## 7. The `relios.toml` schema

Required sections: `[app] [project] [version] [build] [assets] [bundle] [install] [signing]`. Optional: `[dmg] [notarize] [update]` (absent or `enabled = false` → that feature is skipped).

```toml
[app]
name = "MyApp"                  # executable/product name; non-empty (doctor fail if empty)
display_name = "My App"         # Finder name
bundle_id = "com.example.myapp" # FIX after init (default com.example.<name>)
min_macos = "14.0"
category = "public.app-category.developer-tools"

[project]
type = "swiftpm"                # swiftpm | xcodebuild  (set by init)
root = "."
binary_target = "MyApp"         # executable target; non-empty (doctor fail if empty)

[version]
source_file = "AppVersion.swift"
version_pattern = 'static let current = "(.*)"'  # one capture group
build_pattern   = 'static let build = "(.*)"'    # one capture group

[build]
# PREFERRED: argv form — runs WITHOUT a shell (no injection). doctor passes clean.
executable = "swift"
arguments = ["build", "-c", "release"]
# LEGACY: shell string via /bin/sh — doctor WARNS (BUILD_SHELL_COMMAND) unless
# allow_shell = true, because it executes arbitrary code (plugins, run-scripts).
# command = "xcodebuild -scheme MyApp -configuration Release -derivedDataPath build build"
# allow_shell = false
binary_path = ".build/release/MyApp"             # assembly only (empty in passthrough)
resource_bundle_path = ""                        # optional SwiftPM resource bundle

[assets]
icon_path = ""                                   # optional .icns

[bundle]
output_path = "dist/MyApp.app"                   # passthrough: where xcodebuild puts the .app
plist_mode = "generate"                          # ignored in passthrough
mode = "assembly"                                # assembly | passthrough

[install]
path = "/Applications/MyApp.app"
auto_open = true
backup_dir = "dist/app-backups"
keep_backups = 3
quit_running_app = true

[signing]
mode = "adhoc"                                   # adhoc | keep | developer-id
# developer-id also needs:
# identity = "Developer ID Application: Name (TEAM123456)"
# team_id = "TEAM123456"
# hardened_runtime = true                        # default true; required for notarization
# entitlements_path = ""

[dmg]                                            # optional
enabled = true
output_dir = "dist"
volume_name = ""                                 # default: display name
background_color = "#FCF5F3"                     # solid color (no image)
window_size = [540, 360]                         # [width, height]
icon_size = 80

[notarize]                                       # optional; requires developer-id signing
enabled = true
target = "auto"                                  # auto | dmg | zip (auto prefers DMG)
timeout_seconds = 3600
# Credentials are NEVER here — env only: APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID

[update]                                          # optional; auto-update feed + push-to-release
enabled = true
feed_file = "update.json"
output_dir = "dist"
download_url_template = "https://github.com/{repo}/releases/download/{tag}/{asset}"
feed_url = "https://github.com/OWNER/REPO/releases/latest/download/update.json"
sign = true                                       # Ed25519-sign the feed → update.json.sig
```

**Update feed integrity & signing.** `update generate --artifact <localfile>` adds
`sha256` + `size` to `update.json` (the app verifies the download); `--commit`
adds `git_commit` provenance. With `[update].sign = true` and a key
(`relios update keygen` → store as `RELIOS_UPDATE_SIGNING_KEY` secret, or
`--signing-key-file`), it also writes `update.json.sig` (Ed25519). The app embeds
the public key and rejects a feed that doesn't verify — so a hijacked release
asset alone can't push a malicious update. The generated `release.yml` is hardened:
least‑privilege `permissions`, `concurrency`, a tag==AppVersion check, and it
uploads the `.sig`.

**Editing rules for the agent:**
- To enable a feature, add its section with `enabled = true` (or use `relios signing setup` for `[signing]`). Then `relios doctor` to confirm readiness.
- Empty strings normalize to "unset" for optional fields (`icon_path`, `identity`, `volume_name`, `feed_url`, …).
- Changing `[signing].mode` to `developer-id` requires `identity` + `team_id`; prefer `relios signing setup --identity … --team-id …` over hand‑editing (it parses the team from the identity and validates against the keychain).

---

## 8. Playbooks

Each playbook is a copy‑pasteable sequence with the Assess→Proceed→Fix loop baked in. Replace placeholders. Run from the project root.

### Playbook A — Adopt Relios into a SwiftPM app (greenfield, local install)
```bash
# ASSESS
test -f relios.toml && echo "EXISTS - do not init; patch instead" || echo "safe to init"
# PROCEED (only if no relios.toml)
relios init
# FIX the spec: bundle_id is the usual edit
#   (edit [app].bundle_id; verify [project].binary_target matches your executable target)
# ASSESS
relios doctor
#   → resolve any [fail]; [warn] "install path parent missing" → relios doctor --fix
# ASSESS the build with zero writes
relios release patch --dry-run
#   → if it fails at "build", re-run with --verbose, fix the compile error, repeat
# PROCEED
relios release patch
# VERIFY
relios inspect
```

### Playbook B — Adopt into an Xcode/XcodeGen app (passthrough)
```bash
relios init                      # detects .xcodeproj → passthrough
# CRITICAL FIX: verify the guessed scheme + output path
#   [build].command  → -scheme <ACTUAL_SCHEME>
#   [bundle].output_path → where xcodebuild actually writes the .app
relios doctor
relios release patch --dry-run   # a wrong scheme/path fails at "verify build artifact"
#   → fix [build].command / [bundle].output_path until dry-run is clean
relios release patch
relios inspect
```

### Playbook C — Reinstall / relaunch / rollback (operational, no new version)
These are **independent** operations — pick the one that matches the goal. **Do not run them as a sequence** (that would reinstall and then immediately roll it back).
```bash
# Goal: reinstall the already-built .app (backs up first)
relios install
# Goal: relaunch the installed app
relios open
# Goal: inspect available backups
ls dist/app-backups
# Goal: restore the latest backup
relios rollback
# Goal: restore a specific backup
relios rollback --to dist/app-backups/MyApp-v1.2.3-b4.zip
```

### Playbook D — Developer ID signed build
```bash
# ASSESS what's available
relios signing status
# If the cert isn't in the keychain yet:
export RELIOS_CERT_PASSWORD='...'        # ask the human for the .p12 password
relios signing import /path/to/cert.p12
# CONFIGURE non-interactively (never rely on the prompt)
relios signing setup --identity "Developer ID Application: Name (TEAM123456)" --team-id TEAM123456
# ASSESS
relios doctor                            # signing readiness must be [ok]
relios release patch --dry-run           # preflight includes signing readiness
# PROCEED + VERIFY
relios release patch
relios signing verify                    # confirms a valid signature on the .app
```

### Playbook E — DMG packaging
```bash
# Enable [dmg] in relios.toml (enabled = true)
which dmgbuild || pip install dmgbuild    # doctor "dmg readiness" warns if missing
relios doctor
relios release patch --dry-run            # ASSESS: build + verify, zero Relios writes
relios release patch --no-open            # PROCEED: produce the .app (dry-run leaves none)
relios dmg
ls dist/*.dmg
```

### Playbook F — Notarized, distributable build (Developer ID + DMG + notarize)
```bash
# Prereqs: Playbook D done (developer-id signing configured & cert in keychain)
# Enable [dmg] and [notarize] (enabled = true) in relios.toml
export APPLE_ID='you@example.com'
export APPLE_APP_SPECIFIC_PASSWORD='abcd-efgh-ijkl-mnop'   # app-specific, from appleid.apple.com
export APPLE_TEAM_ID='TEAM123456'                          # must equal [signing].team_id
# ASSESS — all of these must be green/ready
relios doctor                # signing readiness [ok], notarize ready (not "requires developer-id")
relios release patch --dry-run
# PROCEED — build, sign
relios release patch
relios signing verify        # GATE: do not notarize an invalidly-signed artifact
relios dmg
# IRREVERSIBLE NETWORK STEP — gate per Section 11
relios notarize              # submits dist/<App>-<ver>.dmg, waits, staples
```

### Playbook G — CI on GitHub Actions
```bash
# ASSESS: ci init is self-gating (refuses to overwrite without --force)
relios ci init
#   → if "workflowExists", inspect the files; re-run with --force only if regen is wanted
git add .github/workflows && git commit -m "Add Relios CI"
relios ci doctor             # checks workflow presence + github remote
# release.yml triggers on a v* tag. Pushing a tag is OUTWARD-FACING (Section 11):
git tag --annotate v0.1.0 --message "Release v0.1.0"
git show v0.1.0
# STOP: confirm with the human before pushing — the push triggers a public release.
# Only after explicit authorization:
git push origin refs/tags/v0.1.0
```
**What gets generated** (conditioned on spec): `ci.yml` (PR/push build+test), `release.yml` (build→sign→DMG→notarize→staple→publish→update‑feed, with only the enabled steps), and — when `[update]` is on — `auto-release.yml`. For signing/notarize in CI, the human must add repo **secrets** (Section 12).

### Playbook H — Auto‑update feed + push‑to‑release automation
```bash
# Add [update] to relios.toml:
#   enabled = true
#   feed_url = "https://github.com/<owner>/<repo>/releases/latest/download/update.json"
relios doctor                          # "update feed configured" [ok]
# Generate the feed locally to sanity-check the shape (preview path):
relios update generate --tag v$(relios version) --repo OWNER/REPO --asset MyApp-$(relios version).dmg --output /tmp/update.preview.json
cat /tmp/update.preview.json
# Wire CI. ci init is self-gating: run WITHOUT --force first.
relios ci init || true        # if it reports "workflowExists", the files already exist
#   → overwriting user-authored workflows is gated (Section 11): inspect the diff and
#     get authorization before `relios ci init --force`.
git add .github/workflows relios.toml && git commit -m "Enable auto-update feed"
# Pushing to main triggers auto-release on a version change — OUTWARD-FACING.
# Confirm with the human before pushing:
git push origin main
```
**Resulting loop the human gets:** bump the version in `AppVersion.swift` → push to `main` → `auto-release.yml` sees the new version (via `relios version`), creates tag `v<version>` → `release.yml` builds/signs/notarizes/publishes and uploads a fresh `update.json` → the shipped app, polling `feed_url`, discovers the update. Unchanged version → no tag, no release.

### Playbook I — Version bump strategy (choosing the argument)
- A bug‑fix / no API change, or "just rebuild and reinstall" → `relios release` (no arg, build +1) or `relios release patch`.
- Backwards‑compatible feature → `relios release minor`.
- Breaking change → `relios release major`.
- "I only changed the version and want to ship it" (with `[update]` + auto‑release) → edit `AppVersion.swift`, `git push origin main`; let CI tag and release.

---

## 9. Decision trees

### 9.1 "The human wants to ship / install a build"
```
Is there a relios.toml?
├─ no  → Playbook A (swiftpm) or B (xcodebuild), then continue below
└─ yes → relios doctor
          ├─ [fail] → fix via Section 10 → re-run doctor
          └─ ok/mostly → relios release <bump> --dry-run
                          ├─ fail → --verbose, fix (Section 10), re-dry-run
                          └─ clean → does the human need distribution (DMG/notarize/feed)?
                                      ├─ no  → relios release <bump>  → inspect
                                      └─ yes → Playbook F / E / H as applicable (gate irreversibles)
```

### 9.2 "Which command produces a `.app` I can install/DMG/notarize?"
```
Need a built .app on disk at [bundle].output_path?
├─ Just verify it would build (no artifact needed) → relios release --dry-run
├─ Just compile-check (no artifact needed) → relios build
├─ Need the actual .app (for dmg / install / notarize) → relios release <bump>   (NOT --dry-run; relios build verifies but does not assemble the .app)
└─ Already built, just install it again → relios install
```

### 9.3 "doctor shows a warning — do I act?"
```
[warn] install path parent missing → relios doctor --fix     (auto)
[warn] dmgbuild not found          → only matters if goal needs DMG → pip install dmgbuild
[warn] notarize credentials not set→ only matters if notarizing locally → set env (Section 12); CI uses secrets
[warn] team_id mismatch            → ALWAYS fix (Apple rejects) → align [signing].team_id and APPLE_TEAM_ID
[warn] update url template missing  → fix template or always pass --download-url in CI
[warn] github remote (ci doctor)   → only matters for CI → add a GitHub remote
```

---

## 10. Failure → remediation matrix

`A` = you can fix autonomously. `H` = needs a human (secret, decision, or hardware/account).

| Where | Reason (substring) | Class | Remediation |
|---|---|---|---|
| any | `relios.toml not found` | A | `relios init` (if no spec) — else you're in the wrong dir; `cd` to project root. |
| init | `No Package.swift or Xcode project found` | A | `cd` to the real project root; or the project isn't a supported type → tell the human. |
| doctor: spec valid | `app.name`/`bundle_id`/`binary_target` is empty | A | Edit `relios.toml` to set the field. |
| doctor: version source | `version_pattern`/`build_pattern` unmatched, or file missing | A | Ensure `[version].source_file` exists and the regex capture matches the file's actual lines; or run `relios init` (writes a matching `AppVersion.swift`) on a fresh project. |
| doctor/dry-run: project type | Xcode markers + assembly mode | A | Set `[bundle].mode = "passthrough"` and `[project].type = "xcodebuild"`. |
| doctor/dry-run: build tool | `swift`/`xcodebuild` not in PATH | A/H | `xcode-select --install` (swift). xcodebuild needs full Xcode + `sudo xcode-select --switch /Applications/Xcode.app` (H if Xcode absent). |
| release at `build` | compile error (see `--verbose` tail) | A | Read the stderr tail, fix the source, re‑dry‑run. |
| release at `verify build artifact` | artifact/.app not found | A | Fix `[build].binary_path` (assembly) or `[build].command` scheme + `[bundle].output_path` (passthrough). |
| doctor/dry-run: signing readiness | `signing.identity`/`team_id` missing | A | `relios signing setup --identity "…" --team-id …`. |
| doctor/dry-run: signing readiness | identity not in keychain | A/H | `relios signing import <p12>` (needs the `.p12` + `RELIOS_CERT_PASSWORD` — H to obtain). |
| doctor: signing readiness | `codesign` not found | A | `xcode-select --install`. |
| doctor: notarize | `requires developer-id signing` | A | Configure developer‑id signing (Playbook D) before enabling `[notarize]`. |
| doctor: notarize | `notarytool not available` | H | Install full Xcode 13+ (CLT alone lacks notarytool). |
| doctor: notarize | `credentials not set` | A/H | `export APPLE_ID/APPLE_APP_SPECIFIC_PASSWORD/APPLE_TEAM_ID` (values are H — the human's account/app‑specific password). |
| notarize | `team_id mismatch` | A | Align `[signing].team_id` with `APPLE_TEAM_ID`. |
| notarize | Apple `status: invalid`/`rejected` | A/H | Read the notary log; usually a signing/hardened‑runtime/entitlements issue → fix signing, re‑sign, resubmit. |
| doctor: dmg | `dmgbuild not found` | A | `pip install dmgbuild` (or `pipx install dmgbuild`). |
| dmg | `.app` missing | A | Run a real `relios release` first (dry‑run leaves no `.app`). |
| install | `appNotFound` | A | Run `relios release` (or build) to produce the `.app`. |
| install/update | `versionReadFailed` | A | Fix `[version]` patterns (same as version‑source check). |
| update generate | `downloadURLUnresolved` | A | Pass `--download-url`, or pass `--repo` + `--asset` so the template resolves. |
| update generate | `updateDisabled` | A | Add `[update]` with `enabled = true`. |
| ci init | `workflowExists` | A/H | Inspect existing files; re‑run with `--force` only if the human wants them regenerated (H if unsure). |
| rollback | `noBackupsFound`/`backupNotFound` | A | `ls dist/app-backups`; pick a valid `--to`, or there's nothing to roll back to. |
| signing import | `env var … is empty or unset` | A/H | `export RELIOS_CERT_PASSWORD='…'` (value is H). |

---

## 11. Reversibility ladder

From safest to most committal. **Above the line = act freely after a green assess. Below the line = gate + (unless durably authorized) confirm with the human.**

```
SAFE / READ-ONLY .... relios doctor, version, inspect, signing status/verify,
                      release --dry-run, ci init (no --force), update generate --output /tmp/…
LOCAL & REVERSIBLE .. relios release, install  (back up first → rollback restores)
                      doctor --fix (additive), signing setup/import (local config/keychain)
                      ci init --force (regenerates local files; git-tracked → diff/revert)
─────────────────────────────────────────────────────────────────────────────
IRREVERSIBLE / OUTWARD-FACING (GATE + CONFIRM):
  • git tag + push           → triggers public CI/release; hard to unpublish
  • GitHub Release publish    → visible artifact; may be cached/indexed
  • relios notarize           → Apple submission: network, minutes, quota; not undoable
  • --skip-backup on release/install → removes your rollback safety net
```
**Gate checklist before any below‑the‑line action:** (1) `relios doctor` green for the relevant checks; (2) for releases, `--dry-run` clean; (3) for notarize, `relios signing verify` passes and all three `APPLE_*` env vars are set; (4) the human asked for this outcome (or durably authorized it). If any is unmet, **stop and report** with the specific blocker and the `Fix:` you'd apply.

**Always stop for the human when:** a secret value is needed (Apple password, `.p12` password, signing identity choice among several), an irreversible/outward action is implied but not explicitly requested, `init`/`ci init --force` would overwrite existing user‑authored config, or `doctor` reports a `[fail]` you cannot remediate autonomously (e.g. install full Xcode).

---

## 11b. Transactions, locks & recovery

Mutating commands (`init`, `release`, `install`, `rollback`, `dmg`, `notarize`, `update generate`, `ci init`, `signing setup`) take a **project lock** at `.relios/lock` for the duration of the run. A second mutating command in the same project while one is running is **refused** (exit nonzero, JSON `error.id` `LOCK_HELD` / `LOCK_HELD_ANOTHER_HOST`) — never run two concurrently. A lock whose holder process is dead (same host) is reclaimed automatically on the next run.

**Crash safety.** The dangerous step — replacing the installed `.app` — uses move‑aside → move‑into‑place → restore‑on‑failure (`install`/`release`), and `rollback` extracts to a scratch dir, validates (zip‑slip + symlink + the expected `.app`), then atomically swaps, restoring the previous app if anything fails. So a *clean* failure self‑heals and never destroys the existing install. A *hard kill* (where cleanup didn't run) can leave a stale lock, a scratch dir, or a stashed previous app.

**Recover from a hard kill — two commands:**
- `relios status` — read‑only: shows the lock holder (and whether it's stale) and any leftover state, plus what `recover` would do. JSON: `data.lock_holder`, `data.lock_stale`, `data.findings[]`, `data.clean`.
- `relios recover [--dry-run]` — clears a stale lock, removes scratch dirs, removes a leftover stash when the install is present, or **restores** the stash when the install is missing (interrupted mid‑swap). Safe and idempotent; `--dry-run` reports without changing anything.

**Agent rule:** if a mutating command fails with `LOCK_HELD*`, run `relios status` — if `lock_stale` is true, run `relios recover` then retry; if false, another run is genuinely active, so wait (don't delete the lock by hand). Run `relios status` at the start of an autonomous session to detect leftover state from a prior crash.

---

## 12. Secrets & environment variables

| Variable | Used by | Notes |
|---|---|---|
| `RELIOS_CERT_PASSWORD` | `signing import` | Password for the `.p12`. Override the var name with `--password-env`. |
| `APPLE_ID` | `notarize` | Apple Developer account email. |
| `APPLE_APP_SPECIFIC_PASSWORD` | `notarize` | App‑specific password (appleid.apple.com → Security), **not** the account password. |
| `APPLE_TEAM_ID` | `notarize` | 10‑char Team ID; must equal `[signing].team_id`. |

**Never** write these into `relios.toml` or commit them. For local runs, `export` them (their values come from the human). For CI, they are **GitHub repo secrets** — the generated `release.yml` references:
- Signing: `APPLE_CERTIFICATE` (base64 of the `.p12`), `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`.
- Notarization: `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`.

You cannot set repo secrets from the spec — instruct the human to add them (e.g. via `gh secret set`), and surface the exact names from the workflow header comments.

---

## 13. Files Relios creates

Know these so you never overwrite user work blindly, and so you can verify outcomes by inspecting them.

| Path | Created by | Notes |
|---|---|---|
| `relios.toml` | `init` (overwrite!), patched by `signing setup` | The spec. Back up before re‑`init`. |
| `AppVersion.swift` | `init` (only if absent) | Version source; rewritten by `release`. |
| `dist/<App>.app` | `release` (assembly) / your `xcodebuild` (passthrough) | `[bundle].output_path`. |
| `dist/<App>-<ver>.dmg` | `dmg` / `release` (CI) | `[dmg].output_dir`. |
| `dist/update.json` | `update generate` | `[update]` feed. |
| `dist/app-backups/*.zip` | `release`/`install` | Rotated to `[install].keep_backups`; source for `rollback`. |
| `dist/releases/latest.json` | `release`/`install` | Latest manifest (read by `inspect`). |
| `dist/releases/history/<ts>.json` | `release`/`install` | Append‑only history. |
| `.github/workflows/release.yml` | `ci init` | Tag‑triggered release pipeline. |
| `.github/workflows/ci.yml` | `ci init` | PR/push build+test. |
| `.github/workflows/auto-release.yml` | `ci init` (only when `[update]`) | Push‑to‑main version‑change → tag. |
| `/Applications/<App>.app` | `release`/`install` | `[install].path`. |

`dist/` is safe to treat as Relios‑owned/disposable (it's typically git‑ignored). `.github/workflows/*` are git‑tracked — diff before regenerating with `--force`.

---

## 14. Quick reference appendix

### Commands & key flags
> Every command below also accepts **`--format human|json`** (or `RELIOS_FORMAT=json`). See [§2b](#2b-structured-output---format-json--preferred-for-agents).
```
relios capabilities                            # bootstrap: cli_version, schema_version, per-command flags
relios init                                   # scaffold spec (OVERWRITES relios.toml)
relios doctor [--fix] [-v]                     # 9 read-only checks (--fix: create install dir)
relios release [patch|minor|major] [--dry-run] [--no-open] [--install-path P] [--skip-backup] [-v]
relios install [--install-path P] [--no-open] [--skip-backup] [-v]
relios open [--install-path P]
relios inspect
relios rollback [--to ZIP] [--no-open] [-v]
relios version [--build | --full]             # app version on stdout (errors on stderr)
relios signing status
relios signing setup [--identity S] [--team-id S] [--hardened-runtime] [--entitlements P] [--non-interactive]
relios signing import P12 [--keychain N] [--password-env VAR]
relios signing verify [APP]
relios dmg [-v]
relios notarize [PATH] [--timeout SEC]
relios update generate --tag T [--repo O/R] [--asset F] [--download-url U] [--artifact LOCALFILE] [--commit SHA] [--signing-key-file K] [--notes S | --notes-file P] [--notes-url U] [--output P]
relios update keygen [--out DIR]               # Ed25519 keypair for signing the feed
relios ci init [--force]
relios ci doctor
relios build [-v]                              # compile + verify artifact; no bump/install
relios capabilities                            # version + output schema + per-command flags
relios status                                  # project lock + leftover state (read-only)
relios recover [--dry-run]                     # clear stale lock + resolve leftover state
```
> Mutating commands hold a project lock at `.relios/lock`; concurrent runs are refused (`LOCK_HELD*`). See [§11b](#11b-transactions-locks--recovery).

### Exit‑code contract
- `0` = success; nonzero = failure, for every command.
- `doctor`: nonzero iff a `[fail]` exists (`[warn]` is `0`).
- `version`: value on stdout, errors on stderr — `V=$(relios version)` is safe.

### The one‑line pre‑flight you can run anywhere
```bash
cd <project-root> && relios doctor && relios release --dry-run
```
Green + "Dry run — no files were written." ⇒ a real `relios release` will (almost certainly) succeed up to and including build/verify; proceed, then `relios inspect` to confirm.

### Coverage map: dry‑run vs doctor
| Concern | `release --dry-run` | `doctor` |
|---|---|---|
| spec valid, version source, build tool, project type | ✅ | ✅ |
| actually builds + verifies the artifact | ✅ | ❌ |
| signing readiness (identity in keychain) | ✅ (preflight) | ✅ |
| install path parent | ❌ | ✅ (`--fix`) |
| dmg / notarize / update readiness | ❌ | ✅ |
Run **both** for a complete picture before a distributable release.

---

*Generated for autonomous agents operating Relios. When in doubt: assess read‑only, prefer `--dry-run`, read the `Fix:` line, keep the backup, and gate anything that reaches outside the machine.*
