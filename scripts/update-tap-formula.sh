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

set -euo pipefail

: "${TAG:?TAG env required}"
: "${SHA256:?SHA256 env required}"
: "${TAP_TOKEN:?TAP_TOKEN env required}"

TAP_REPO="${TAP_REPO:-papa-channy/homebrew-relios}"
SRC_REPO="${SRC_REPO:-papa-channy/relios}"
FORMULA_PATH="${FORMULA_PATH:-Formula/relios.rb}"
API="https://api.github.com/repos/${TAP_REPO}/contents/${FORMULA_PATH}"
NEW_URL="https://github.com/${SRC_REPO}/archive/refs/tags/${TAG}.tar.gz"

log() { printf '[tap-update] %s\n' "$*" >&2; }

log "TAG=$TAG"
log "SHA256=$SHA256"
log "NEW_URL=$NEW_URL"

# Fetch current formula.
RESP=$(curl -fsSL \
  -H "Authorization: Bearer $TAP_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API")

CUR_SHA=$(printf '%s' "$RESP" | jq -r .sha)
CUR_CONTENT=$(printf '%s' "$RESP" | jq -r .content | base64 -d)

# Replace url line (anchored on archive/refs/tags/) and first sha256 line.
NEW_CONTENT=$(printf '%s' "$CUR_CONTENT" \
  | sed -E "s|^([[:space:]]*url \")[^\"]*archive/refs/tags/[^\"]*(\".*)\$|\\1${NEW_URL}\\2|" \
  | awk -v sha="$SHA256" '
      BEGIN { done = 0 }
      {
        if (!done && $0 ~ /^[[:space:]]*sha256 "[0-9a-f]+"/) {
          sub(/sha256 "[0-9a-f]+"/, "sha256 \"" sha "\"")
          done = 1
        }
        print
      }
    ')

if [ "$NEW_CONTENT" = "$CUR_CONTENT" ]; then
  log "Formula already at $TAG with sha $SHA256 — no-op"
  exit 0
fi

# Sanity: the new content must contain both the new URL and the new sha256.
if ! printf '%s' "$NEW_CONTENT" | grep -qF "$NEW_URL"; then
  log "ERROR: sed did not produce expected url line"
  exit 1
fi
if ! printf '%s' "$NEW_CONTENT" | grep -qF "$SHA256"; then
  log "ERROR: sha256 substitution failed"
  exit 1
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  log "DRY_RUN=1 — printing diff and exiting"
  diff <(printf '%s' "$CUR_CONTENT") <(printf '%s' "$NEW_CONTENT") || true
  log "Would commit: chore: bump relios to ${TAG}"
  exit 0
fi

# Base64 encode without line wrapping. macOS and GNU coreutils differ:
# use tr to strip newlines for portability.
NEW_B64=$(printf '%s' "$NEW_CONTENT" | base64 | tr -d '\n')

PAYLOAD=$(jq -n \
  --arg msg "chore: bump relios to ${TAG}" \
  --arg content "$NEW_B64" \
  --arg sha "$CUR_SHA" \
  --arg branch "main" \
  '{message:$msg, content:$content, sha:$sha, branch:$branch}')

log "PUT ${API}"
HTTP_CODE=$(curl -sS -o /tmp/tap-put-resp.json -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $TAP_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  --data "$PAYLOAD" \
  "$API")

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
  log "ERROR: PUT returned $HTTP_CODE"
  cat /tmp/tap-put-resp.json >&2
  exit 1
fi

COMMIT_SHA=$(jq -r .commit.sha /tmp/tap-put-resp.json)
log "OK — tap commit ${COMMIT_SHA}"
