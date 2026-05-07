#!/bin/bash
# Flashy — Apple Watch / Pushover notifications for Claude Code
# Sends a Pushover push (delivered to phone + Apple Watch) on Stop
# and Notification hook events. Runs alongside flash.sh.

# --- Config ---
# Source user config first; defaults fill in anything unset.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flashy"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"

PUSHOVER_ENABLED="${PUSHOVER_ENABLED:-true}"
PUSHOVER_USER_KEY="${PUSHOVER_USER_KEY:-}"
PUSHOVER_APP_TOKEN="${PUSHOVER_APP_TOKEN:-}"
PUSHOVER_TITLE="${PUSHOVER_TITLE:-Claude Code}"
PUSHOVER_STOP_MESSAGE="${PUSHOVER_STOP_MESSAGE:-Claude finished a turn}"
PUSHOVER_NOTIFICATION_MESSAGE="${PUSHOVER_NOTIFICATION_MESSAGE:-Claude needs your attention}"
PUSHOVER_PRIORITY="${PUSHOVER_PRIORITY:-0}"
PUSHOVER_SOUND="${PUSHOVER_SOUND:-}"
PUSHOVER_TIMEOUT="${PUSHOVER_TIMEOUT:-5}"

# Silently skip if disabled, sentinel file present, missing creds, or no curl.
# Hooks must always exit 0 — never surface errors to Claude Code.
[ "$PUSHOVER_ENABLED" = "false" ] && exit 0
[ -e "$CONFIG_DIR/pushover-disabled" ] && exit 0
[ -z "$PUSHOVER_USER_KEY" ] && exit 0
[ -z "$PUSHOVER_APP_TOKEN" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0

# --- Resolve message from event name ---
case "$1" in
  stop)         MESSAGE="$PUSHOVER_STOP_MESSAGE" ;;
  notification) MESSAGE="$PUSHOVER_NOTIFICATION_MESSAGE" ;;
  *)            MESSAGE="${1:-Claude Code event}" ;;
esac

# --- Send notification (backgrounded so the hook returns instantly) ---
ARGS=(
  --silent
  --max-time "$PUSHOVER_TIMEOUT"
  --form-string "token=$PUSHOVER_APP_TOKEN"
  --form-string "user=$PUSHOVER_USER_KEY"
  --form-string "title=$PUSHOVER_TITLE"
  --form-string "message=$MESSAGE"
  --form-string "priority=$PUSHOVER_PRIORITY"
)
[ -n "$PUSHOVER_SOUND" ] && ARGS+=( --form-string "sound=$PUSHOVER_SOUND" )

(
  curl "${ARGS[@]}" https://api.pushover.net/1/messages.json \
    </dev/null >/dev/null 2>&1
) &
disown 2>/dev/null

exit 0
