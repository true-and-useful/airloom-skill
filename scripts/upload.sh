#!/usr/bin/env bash
set -euo pipefail

# airloom upload script — uploads audio and gets a shareable episode URL.
# Dependencies: curl, jq, file (optional but recommended)

AIRLOOM_BASE_URL="https://airloom.fm"
ALLOW_CUSTOM_BASE=false

# --- helpers ----------------------------------------------------------------

die()  { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
emit() { echo "$1" >&2; }

usage() {
  cat >&2 <<'EOF'
Usage: upload.sh <audio-file> [options]

Options:
  --title <text>                   Episode title (default: filename)
  --description <text>             Episode description
  --client <name>                  Agent attribution (e.g. cursor, claude-code)
  --api-key <key>                  API key override (prefer credentials file)
  --base-url <url>                 API base (default: https://airloom.fm)
  --allow-nonairloom-base-url      Required when using --base-url
EOF
  exit 1
}

# --- dependency checks ------------------------------------------------------

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required but not installed"
done

HAS_FILE_CMD=false
if command -v file >/dev/null 2>&1; then
  HAS_FILE_CMD=true
fi

# --- parse args -------------------------------------------------------------

AUDIO_FILE=""
TITLE=""
DESCRIPTION=""
CLIENT=""
API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --client)      CLIENT="$2"; shift 2 ;;
    --api-key)     API_KEY="$2"; shift 2 ;;
    --base-url)    AIRLOOM_BASE_URL="$2"; shift 2 ;;
    --allow-nonairloom-base-url) ALLOW_CUSTOM_BASE=true; shift ;;
    --help|-h)     usage ;;
    -*)            die "unknown option: $1" ;;
    *)
      [[ -z "$AUDIO_FILE" ]] || die "unexpected argument: $1"
      AUDIO_FILE="$1"; shift ;;
  esac
done

[[ -n "$AUDIO_FILE" ]] || usage

# --- base URL safety --------------------------------------------------------

if [[ "$AIRLOOM_BASE_URL" != "https://airloom.fm" ]]; then
  if [[ "$ALLOW_CUSTOM_BASE" != "true" ]]; then
    die "refusing to send credentials to non-airloom URL: $AIRLOOM_BASE_URL (pass --allow-nonairloom-base-url to override)"
  fi
  warn "*** USING NON-STANDARD BASE URL: $AIRLOOM_BASE_URL ***"
  warn "*** Your API key will be sent to this server. Proceed only if you trust it. ***"
fi

# --- resolve API key --------------------------------------------------------

API_KEY_SOURCE="none"

if [[ -n "$API_KEY" ]]; then
  API_KEY_SOURCE="flag"
elif [[ -n "${AIRLOOM_API_KEY:-}" ]]; then
  API_KEY="$AIRLOOM_API_KEY"
  API_KEY_SOURCE="env"
elif [[ -f "$HOME/.airloom/credentials" ]]; then
  API_KEY="$(cat "$HOME/.airloom/credentials" | tr -d '[:space:]')"
  API_KEY_SOURCE="credentials_file"
fi

# --- validate file ----------------------------------------------------------

[[ -f "$AUDIO_FILE" ]] || die "file not found: $AUDIO_FILE"

ALLOWED_MIMES="audio/mpeg audio/mp4 audio/x-m4a audio/ogg"

if [[ "$HAS_FILE_CMD" == "true" ]]; then
  DETECTED_MIME="$(file --brief --mime-type "$AUDIO_FILE")"
  MIME_OK=false
  for m in $ALLOWED_MIMES; do
    [[ "$DETECTED_MIME" == "$m" ]] && MIME_OK=true
  done
  if [[ "$MIME_OK" != "true" ]]; then
    die "unsupported audio format: $DETECTED_MIME (expected: $ALLOWED_MIMES)"
  fi
else
  warn "'file' command not found — skipping MIME type check"
fi

# --- default title from filename --------------------------------------------

if [[ -z "$TITLE" ]]; then
  TITLE="$(basename "$AUDIO_FILE")"
  # strip extension
  TITLE="${TITLE%.*}"
fi

# --- build curl args --------------------------------------------------------

CURL_ARGS=(
  -sS
  --fail-with-body
  -X POST
  "${AIRLOOM_BASE_URL}/api/v1/upload"
  -F "file=@${AUDIO_FILE}"
  -F "title=${TITLE}"
)

[[ -n "$DESCRIPTION" ]] && CURL_ARGS+=(-F "description=${DESCRIPTION}")

if [[ -n "$API_KEY" ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer ${API_KEY}")
fi

if [[ -n "$CLIENT" ]]; then
  CURL_ARGS+=(-H "X-Airloom-Client: ${CLIENT}/upload-sh")
fi

# --- upload -----------------------------------------------------------------

HTTP_RESPONSE="$(curl "${CURL_ARGS[@]}")" || {
  # try to extract error from JSON response
  ERR="$(echo "$HTTP_RESPONSE" | jq -r '.error // empty' 2>/dev/null)"
  if [[ -n "$ERR" ]]; then
    die "upload failed: $ERR"
  else
    die "upload failed (server returned an error)"
  fi
}

# validate response is JSON with a slug
SLUG="$(echo "$HTTP_RESPONSE" | jq -r '.slug // empty')"
[[ -n "$SLUG" ]] || die "unexpected response: missing slug"

# --- parse response ---------------------------------------------------------

EPISODE_URL="$(echo "$HTTP_RESPONSE" | jq -r '.url')"
AUDIO_URL="$(echo "$HTTP_RESPONSE" | jq -r '.audioUrl')"
CLAIM_TOKEN="$(echo "$HTTP_RESPONSE" | jq -r '.claimToken // empty')"
EXPIRES_AT="$(echo "$HTTP_RESPONSE" | jq -r '.expiresAt // empty')"
QR="$(echo "$HTTP_RESPONSE" | jq -r '.qr // empty')"

# determine auth mode
if [[ -n "$CLAIM_TOKEN" ]]; then
  AUTH_MODE="anonymous"
  PERSISTENCE="expires_24h"
else
  AUTH_MODE="authenticated"
  PERSISTENCE="permanent"
fi

# --- update state file ------------------------------------------------------

STATE_DIR=".airloom"
STATE_FILE="${STATE_DIR}/state.json"
mkdir -p "$STATE_DIR"

# build episode entry
EPISODE_JSON="$(jq -n \
  --arg url "$EPISODE_URL" \
  --arg audioUrl "$AUDIO_URL" \
  --arg claimToken "$CLAIM_TOKEN" \
  --arg expiresAt "$EXPIRES_AT" \
  '{url: $url, audioUrl: $audioUrl} +
   (if $claimToken != "" then {claimToken: $claimToken} else {} end) +
   (if $expiresAt != "" then {expiresAt: $expiresAt} else {} end)'
)"

# merge with existing state if present
if [[ -f "$STATE_FILE" ]]; then
  EXISTING="$(cat "$STATE_FILE")"
else
  EXISTING='{"episodes":{}}'
fi

echo "$EXISTING" | jq \
  --arg slug "$SLUG" \
  --argjson entry "$EPISODE_JSON" \
  '.episodes[$slug] = $entry' > "$STATE_FILE"

# --- stdout: episode URL only -----------------------------------------------

echo "$EPISODE_URL"

# --- stderr: structured output for agent parsing ----------------------------

emit "upload_result.episode_url=${EPISODE_URL}"
emit "upload_result.audio_url=${AUDIO_URL}"
emit "upload_result.auth_mode=${AUTH_MODE}"
emit "upload_result.api_key_source=${API_KEY_SOURCE}"
emit "upload_result.persistence=${PERSISTENCE}"

[[ -n "$EXPIRES_AT" ]]  && emit "upload_result.expires_at=${EXPIRES_AT}"
[[ -n "$CLAIM_TOKEN" ]] && emit "upload_result.claim_token=${CLAIM_TOKEN}"

if [[ -n "$QR" ]]; then
  emit "upload_result.qr=${QR}"
fi
