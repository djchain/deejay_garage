#!/bin/sh

BARK_NOTIFY_DEFAULT_LEVEL="${BARK_NOTIFY_DEFAULT_LEVEL:-active}"
BARK_NOTIFY_DEFAULT_GROUP="${BARK_NOTIFY_DEFAULT_GROUP:-Mac}"

bark_notify() {
  title="${1:-}"
  body="${2:-}"
  level="${3:-$BARK_NOTIFY_DEFAULT_LEVEL}"
  group="${4:-$BARK_NOTIFY_DEFAULT_GROUP}"

  if [ -z "$title" ]; then
    echo "bark_notify: missing title" >&2
    return 2
  fi

  if ! command -v bark >/dev/null 2>&1; then
    echo "bark_notify: bark command not found" >&2
    return 127
  fi

  bark -l "$level" -g "$group" "$title" "$body"
}

bark_notify_success() {
  title="${1:-Task finished}"
  body="${2:-The Mac job completed successfully.}"
  bark_notify "$title" "$body" "active" "${3:-$BARK_NOTIFY_DEFAULT_GROUP}"
}

bark_notify_failure() {
  title="${1:-Task failed}"
  body="${2:-The Mac job failed. Check the terminal output.}"
  bark_notify "$title" "$body" "timeSensitive" "${3:-$BARK_NOTIFY_DEFAULT_GROUP}"
}

bark_notify_run() {
  if [ "$#" -eq 0 ]; then
    echo "bark_notify_run: missing command" >&2
    return 2
  fi

  if ! command -v bark >/dev/null 2>&1; then
    echo "bark_notify_run: bark command not found" >&2
    return 127
  fi

  bark run -- "$@"
}
