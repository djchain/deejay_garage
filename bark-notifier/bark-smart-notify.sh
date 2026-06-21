#!/bin/bash
# ============================================================================
# bark-smart-notify.sh -- Unified Bark notification intelligence script
#
# Two modes:
#   1. Direct args:   bark-smart-notify.sh -t "Title" -b "Body" [-l level]
#   2. Hook (stdin):  bark-smart-notify.sh
#                        (reads JSON from stdin, extracts transcript_path,
#                         parses JSONL transcript, generates notification)
#
# Hook mode handles Stop events by parsing the transcript for the last
# assistant message content.  StopFailure and PermissionRequest are
# handled by the hook script which passes explicit -t/-b args instead.
#
# Falls back from Bridge to direct curl if Bridge is unreachable.
# ============================================================================

set -u

CONFIG_FILE="${BARK_CONFIG:-$HOME/.config/bark/bark.env}"
DEFAULT_SERVER="https://api.day.app"

# ── Load Bark config ──────────────────────────────────────────────────
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
  BARK_SERVER="${BARK_SERVER:-$DEFAULT_SERVER}"
  BARK_GROUP="${BARK_GROUP:-Mac}"
}

# ── Categorize notification by content ────────────────────────────────
# Sets globals: PREFIX, LEVEL
categorize() {
  local text="$1"
  local first_sentence
  first_sentence=$(echo "$text" | head -1 | tr -d '\n')

  # Contains "?" in first sentence
  if echo "$first_sentence" | grep -q '?'; then
    PREFIX="❓"
    LEVEL="active"
    return
  fi

  # Permission-related keywords anywhere in text
  if echo "$text" | grep -qiE 'approve|allow|permission|permit|authorize'; then
    PREFIX="🔐"
    LEVEL="timeSensitive"
    return
  fi

  # Default
  PREFIX="🤖"
  LEVEL="passive"
}

# ── Title from first ~60 meaningful characters ────────────────────────
generate_title() {
  local text="$1"
  local prefix="$2"
  local max_len=60
  local trimmed
  trimmed=$(echo "$text" | sed 's/^[[:space:]]*//' | cut -c1-60)
  local trimmed_len
  trimmed_len=$(printf '%s' "$trimmed" | wc -c | tr -d ' ')

  if [ "$trimmed_len" -ge "$max_len" ]; then
    echo "${prefix} ${trimmed}..."
  else
    echo "${prefix} ${trimmed}"
  fi
}

# ── Send directly to Bark API via curl ────────────────────────────────
send_bark_curl() {
  local title="$1"
  local body="$2"
  local level="${3:-passive}"

  if [ -z "${BARK_DEVICE_KEY:-}" ]; then
    echo "bark-smart-notify: BARK_DEVICE_KEY not set" >&2
    return 1
  fi

  # Never send empty notification
  if [ -z "$title" ] && [ -z "$body" ]; then
    echo "bark-smart-notify: skipping empty notification" >&2
    return 0
  fi

  local endpoint="${BARK_SERVER%/}/push"
  curl -fsS -X POST "$endpoint" \
    --data-urlencode "device_key=$BARK_DEVICE_KEY" \
    --data-urlencode "title=$title" \
    --data-urlencode "body=$body" \
    --data-urlencode "level=$level" \
    --data-urlencode "group=${BARK_GROUP:-Mac}" \
    --max-time 10 \
    -o /dev/null 2>/dev/null
}

# ── Send via Bridge POST /bark (if BARK_BRIDGE_URL configured) ────────
send_bark_bridge() {
  local title="$1"
  local body="$2"
  local level="${3:-passive}"

  if [ -z "${BARK_BRIDGE_URL:-}" ]; then
    return 1
  fi

  local payload
  if command -v jq >/dev/null 2>&1; then
    payload=$(jq -n -c \
      --arg t "$title" \
      --arg b "$body" \
      --arg l "$level" \
      --arg g "${BARK_GROUP:-Mac}" \
      '{title: $t, body: $b, level: $l, group: $g}')
  else
    payload=$(printf '{"title":"%s","body":"%s","level":"%s","group":"%s"}' \
      "$(echo "$title" | sed 's/"/\\"/g')" \
      "$(echo "$body" | sed 's/"/\\"/g')" \
      "$(echo "$level" | sed 's/"/\\"/g')" \
      "$(echo "${BARK_GROUP:-Mac}" | sed 's/"/\\"/g')")
  fi

  curl -fsS -X POST "${BARK_BRIDGE_URL%/}/bark" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 10 \
    -o /dev/null 2>/dev/null
}

# ── Send notification: Bridge first, fall back to direct curl ─────────
send_bark() {
  local title="$1"
  local body="$2"
  local level="${3:-passive}"

  if [ -n "${BARK_BRIDGE_URL:-}" ]; then
    if send_bark_bridge "$title" "$body" "$level"; then
      return 0
    fi
    echo "bark-smart-notify: bridge unreachable, falling back to curl" >&2
  fi

  send_bark_curl "$title" "$body" "$level"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "bark-smart-notify: curl send failed (exit $rc)" >&2
  fi
  return "$rc"
}

# ── Extract last assistant text from JSONL transcript ────────────────
extract_last_assistant() {
  local transcript_file="$1"

  if [ ! -f "$transcript_file" ]; then
    echo "bark-smart-notify: transcript not found: $transcript_file" >&2
    return 1
  fi

  local combined=""

  if command -v jq >/dev/null 2>&1; then
    # macOS has no 'tac'.  Use grep to find the line number of the last
    # assistant message, then extract text from that line.
    local last_line
    last_line=$(grep -n '"type":"assistant"' "$transcript_file" | tail -1 | cut -d: -f1)
    if [ -n "$last_line" ]; then
      combined=$(sed -n "${last_line}p" "$transcript_file" | \
        jq -r '.message.content[]? | select(.type == "text") | .text' 2>/dev/null | \
        tr '\n' ' ' | sed 's/  */ /g')
    fi
  fi

  if [ -z "$combined" ]; then
    echo "bark-smart-notify: no assistant text found in transcript" >&2
    return 1
  fi

  echo "$combined"
}

# ── Handle hook stdin mode (Stop event) ───────────────────────────────
handle_hook() {
  local event_json
  event_json=$(cat /dev/stdin 2>/dev/null || echo "{}")

  local event_name
  event_name=$(echo "$event_json" | jq -r '.hook_event_name // ""' 2>/dev/null)

  case "$event_name" in
    Stop)
      local stop_reason
      stop_reason=$(echo "$event_json" | jq -r '.stop_reason // "done"' 2>/dev/null)
      if [ "$stop_reason" = "compact" ]; then
        return 0
      fi

      local transcript_path
      transcript_path=$(echo "$event_json" | jq -r '.transcript_path // ""' 2>/dev/null)
      if [ -z "$transcript_path" ] || [ "$transcript_path" = "null" ]; then
        transcript_path=$(echo "$event_json" | jq -r '.metadata.transcript_path // ""' 2>/dev/null)
      fi

      local assistant_text=""
      if [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ]; then
        assistant_text=$(extract_last_assistant "$transcript_path") || true
      fi

      if [ -z "$assistant_text" ]; then
        # No assistant text found — silently skip. Don't send empty notification.
        return 0
      fi

      PREFIX=""
      LEVEL="passive"
      categorize "$assistant_text"
      local title
      title=$(generate_title "$assistant_text" "$PREFIX")
      local body
      body=$(echo "$assistant_text" | sed 's/^[[:space:]]*//')
      send_bark "$title" "$body" "$LEVEL"
      ;;

    *)
      # Unknown event -- silently ignore
      return 0
  esac
}

# ════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════

load_config

TITLE=""
BODY=""
LEVEL=""
PREFIX=""

while getopts ":t:b:l:" opt; do
  case $opt in
    t) TITLE="$OPTARG" ;;
    b) BODY="$OPTARG" ;;
    l) LEVEL="$OPTARG" ;;
    \?) echo "Usage: $(basename "$0") [-t title -b body -l level]" >&2; exit 1 ;;
  esac
done

if [ -n "$TITLE" ] && [ -n "$BODY" ]; then
  # ── Direct mode ─────────────────────────────────────────────────
  if [ -z "$LEVEL" ]; then
    PREFIX="🤖"
    LEVEL="passive"
    categorize "$BODY"
    TITLE="${PREFIX}${TITLE}"
  fi
  send_bark "$TITLE" "$BODY" "$LEVEL"
  exit $?
fi

if [ -t 0 ]; then
  # No stdin and no args -- nothing to do
  echo "Usage: $(basename "$0") [-t title -b body -l level]" >&2
  exit 1
fi

# ── Hook mode (stdin has data) ────────────────────────────────────────
handle_hook
exit $?
