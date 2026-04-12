#!/usr/bin/env bash
# Update Formula/relios.rb in papa-channy/homebrew-relios via GitHub Contents API.
#
# Required env:
#   TAG        e.g. v0.1.0
#   SHA256     64-hex digest of the source tarball
#   TAP_TOKEN  PAT with contents:write on the tap repo
#
# Optional env:
#   DRY_RUN=1  print diff + intended commit message, skip PUT
#   TAP_REPO   default: papa-channy/homebrew-relios
#   SRC_REPO   default: papa-channy/relios
#   FORMULA_PATH default: Formula/relios.rb
#
# Exits 0 on success or no-op; non-zero on any error.
#
# Sourcing this script (e.g. from tests) defines functions without running main.

set -euo pipefail

log() { printf '[tap-update] %s\n' "$*" >&2; }

# Clean up a temp response file created in main(). Defaults to empty so
# `set -u` does not trip when main() exits before the file is allocated.
resp_file=""
trap 'if [ -n "${resp_file:-}" ]; then rm -f "$resp_file"; fi' EXIT

# transform_formula stdin → stdout
# Rewrites the `url` line anchored on `archive/refs/tags/` and the first
# `sha256 "..."` line. Does not touch other occurrences (e.g. bottle blocks).
# Inputs: $1=tag  $2=sha256  $3=src_repo (owner/name)
# NOTE: tag and sha256 are embedded into sed/awk patterns — callers must only
# pass values that have already been validated as safe (semver-ish tag, hex sha).
transform_formula() {
  local tag="$1"
  local sha="$2"
  local src_repo="$3"
  local new_url="https://github.com/${src_repo}/archive/refs/tags/${tag}.tar.gz"
  # The url regex is anchored to GitHub's source-tarball path. If the Formula
  # ever switches to a release asset, a tarball mirror, or adds a bottle block
  # with its own `url`, update this regex (and expand the bats tests).
  sed -E "s|^([[:space:]]*url \")[^\"]*archive/refs/tags/[^\"]*(\".*)\$|\\1${new_url}\\2|" \
    | awk -v sha="$sha" '
        BEGIN { done = 0 }
        {
          if (!done && $0 ~ /^[[:space:]]*sha256 "[0-9a-fA-F]{64}"/) {
            sub(/sha256 "[0-9a-fA-F]+"/, "sha256 \"" sha "\"")
            done = 1
          }
          print
        }
      '
}

main() {
  : "${TAG:?TAG env required}"
  : "${SHA256:?SHA256 env required}"
  : "${TAP_TOKEN:?TAP_TOKEN env required}"

  local tap_repo="${TAP_REPO:-papa-channy/homebrew-relios}"
  local src_repo="${SRC_REPO:-papa-channy/relios}"
  local formula_path="${FORMULA_PATH:-Formula/relios.rb}"
  local api="https://api.github.com/repos/${tap_repo}/contents/${formula_path}"
  local new_url="https://github.com/${src_repo}/archive/refs/tags/${TAG}.tar.gz"

  log "TAG=$TAG"
  log "SHA256=$SHA256"
  log "NEW_URL=$new_url"

  local resp cur_sha cur_content new_content
  resp=$(curl --fail-with-body -sSL --max-time 30 \
    -H "Authorization: Bearer $TAP_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$api")

  cur_sha=$(printf '%s' "$resp" | jq -r .sha)
  cur_content=$(printf '%s' "$resp" | jq -r .content | base64 -d)

  new_content=$(printf '%s' "$cur_content" | transform_formula "$TAG" "$SHA256" "$src_repo")

  if [ "$new_content" = "$cur_content" ]; then
    log "Formula already at $TAG with sha $SHA256 — no-op"
    exit 0
  fi

  if ! printf '%s' "$new_content" | grep -qF "$new_url"; then
    log "ERROR: sed did not produce expected url line"
    exit 1
  fi
  if ! printf '%s' "$new_content" | grep -qF "$SHA256"; then
    log "ERROR: sha256 substitution failed"
    exit 1
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "DRY_RUN=1 — printing diff and exiting"
    diff <(printf '%s' "$cur_content") <(printf '%s' "$new_content") || true
    log "Would commit: chore: bump relios to ${TAG}"
    exit 0
  fi

  local new_b64 payload http_code commit_sha
  new_b64=$(printf '%s' "$new_content" | base64 | tr -d '\n')

  payload=$(jq -n \
    --arg msg "chore: bump relios to ${TAG}" \
    --arg content "$new_b64" \
    --arg sha "$cur_sha" \
    --arg branch "main" \
    '{message:$msg, content:$content, sha:$sha, branch:$branch}')

  log "PUT ${api}"
  # resp_file is intentionally global so the EXIT trap (set at script scope)
  # can still resolve it under `set -u` after main() returns.
  resp_file=$(mktemp)
  http_code=$(curl -sS --max-time 30 -o "$resp_file" -w '%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer $TAP_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    "$api")

  if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
    log "ERROR: PUT returned $http_code"
    cat "$resp_file" >&2
    exit 1
  fi

  commit_sha=$(jq -r .commit.sha "$resp_file")
  log "OK — tap commit ${commit_sha}"
}

# Only run main when executed directly (not when sourced by tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
