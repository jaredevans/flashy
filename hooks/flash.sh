#!/bin/bash
# Flashy — terminal flash notifications for Claude Code
# Pulses the terminal background color on Stop and Notification hook events.

# --- Config ---
# Source user config first (if it exists), then apply defaults for anything unset.
# Order matters: source first so ${VAR:-default} acts as a true fallback.
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flashy"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"

ENABLED="${ENABLED:-true}"
FLASHY_DEBUG="${FLASHY_DEBUG:-false}"

# Debug log — set FLASHY_DEBUG=true in config to trace hook firing.
# Records that the script ran at all, which is the only way to tell a
# non-firing hook from a firing hook whose escape sequence went nowhere.
debug_log() {
  [ "$FLASHY_DEBUG" = "true" ] || return 0
  printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "${1:-?}" "$2" >> "$CONFIG_DIR/debug.log" 2>/dev/null
}

# Guarded, not just handed to debug_log: bash expands arguments before the
# callee can return early, so an unguarded call would run ps on every event.
if [ "$FLASHY_DEBUG" = "true" ]; then
  debug_log "$1" "invoked pid=$$ ppid=$PPID ptty=$(ps -p $PPID -o tty= 2>/dev/null | tr -d ' ') open_devtty=$( ( : > /dev/tty ) 2>/dev/null && echo OK || echo FAIL)"
fi
STOP_PULSES="${STOP_PULSES:-1}"
NOTIFICATION_PULSES="${NOTIFICATION_PULSES:-2}"
WAITING_PULSES="${WAITING_PULSES:-2}"
ERROR_PULSES="${ERROR_PULSES:-3}"
IDLE_PULSES="${IDLE_PULSES:-2}"
PULSE_DURATION="${PULSE_DURATION:-0.22}"
PULSE_GAP="${PULSE_GAP:-0.1}"
SHIFT="${SHIFT:-50}"
FALLBACK_COLOR="${FALLBACK_COLOR:-#1a1b26}"
BG_COLOR_FILE="${BG_COLOR_FILE:-}"

# Early exit if disabled
[ "$ENABLED" = "false" ] && exit 0

# --- Resolve pulse count from event name ---
# Labels are assigned in hooks.json, not taken from the hook event name:
#   stop         Stop
#   error        StopFailure
#   notification Notification (permission/idle/elicitation/agent types)
#   waiting      PreToolUse for AskUserQuestion and ExitPlanMode
#   idle         TeammateIdle
case "$1" in
  stop)         COUNT="$STOP_PULSES" ;;
  notification) COUNT="$NOTIFICATION_PULSES" ;;
  waiting)      COUNT="$WAITING_PULSES" ;;
  error)        COUNT="$ERROR_PULSES" ;;
  idle)         COUNT="$IDLE_PULSES" ;;
  *)            COUNT=1 ;;
esac

# --- Resolve a terminal to draw on ---
# Claude Code runs hooks detached from the controlling terminal, so /dev/tty
# cannot be opened even though the parent process has one. Writing there fails
# silently and nothing ever reaches the terminal. Fall back to the parent's
# TTY device, which is writable from the detached child.
# Also reports whether we own the terminal (OWN_TTY=1) or borrowed the
# parent's (OWN_TTY=0). That distinction gates the OSC 11 *query*: reading a
# response from a terminal we don't control would race the Claude Code TUI for
# the user's keystrokes. Writing is safe either way; reading is not.
OWN_TTY=0
resolve_tty() {
  ( : > /dev/tty ) 2>/dev/null && { OWN_TTY=1; printf '/dev/tty'; return 0; }
  local name
  name=$(ps -p $PPID -o tty= 2>/dev/null | tr -d ' ')
  case "$name" in ''|'??'|'?') return 1 ;; esac
  ( : > "/dev/$name" ) 2>/dev/null && { printf '/dev/%s' "$name"; return 0; }
  return 1
}

# Command substitution runs resolve_tty in a subshell, so the OWN_TTY it sets
# is discarded — re-derive it here from the device that came back.
if TTY_DEV=$(resolve_tty); then
  [ "$TTY_DEV" = "/dev/tty" ] && OWN_TTY=1
else
  TTY_DEV=""
fi
debug_log "$1" "tty_dev=${TTY_DEV:-NONE}"

# No writable terminal (piped context, CI, detached session) — nothing to draw.
[ -z "$TTY_DEV" ] && exit 0

# --- Background color detection (three-tier) ---

# Tier 1: Read from per-TTY color file
# For multi-theme setups where the shell writes bg color to a file per TTY.
detect_from_file() {
  [ -z "$BG_COLOR_FILE" ] && return 1
  # Resolve TTY name (e.g., ttys002) for the {tty} placeholder
  local tty_name
  tty_name=$(ps -p $PPID -o tty= 2>/dev/null | tr -d ' ')
  [ -z "$tty_name" ] && return 1
  local path="${BG_COLOR_FILE//\{tty\}/$tty_name}"
  [ -f "$path" ] && cat "$path" 2>/dev/null && return 0
  return 1
}

# Tier 2: Query terminal via OSC 11
# Sends escape sequence asking the terminal for its current bg color.
# Terminal responds with rgb:RRRR/GGGG/BBBB (16-bit hex per channel).
# Not all terminals support this; /dev/tty reads in subprocess context
# are best-effort. Fails silently → falls through to Tier 3.
detect_from_osc11() {
  local response=""
  # Only safe when we own the terminal — see resolve_tty().
  [ "$OWN_TTY" = "1" ] || return 1
  # Redirect stdin from terminal for reading the response
  exec < "$TTY_DEV" 2>/dev/null || return 1
  # Send the query
  printf '\033]11;?\a' > "$TTY_DEV" 2>/dev/null
  # Read with short timeout — terminal may not respond
  read -t 0.1 -r response 2>/dev/null || return 1

  # Extract the rgb: portion
  local rgb="${response#*rgb:}"       # strip everything before "rgb:"
  rgb="${rgb%%[^0-9a-fA-F/]*}"        # strip everything after hex/slash chars

  # Expect: RRRR/GGGG/BBBB (4 hex digits per channel)
  if [[ "$rgb" =~ ^([0-9a-fA-F]{4})/([0-9a-fA-F]{4})/([0-9a-fA-F]{4})$ ]]; then
    # Take high byte of each 16-bit channel → 8-bit color
    local r="${BASH_REMATCH[1]:0:2}"
    local g="${BASH_REMATCH[2]:0:2}"
    local b="${BASH_REMATCH[3]:0:2}"
    printf '#%s%s%s' "$r" "$g" "$b"
    return 0
  fi
  return 1
}

# Run detection cascade
BG_COLOR=$(detect_from_file) ||
BG_COLOR=$(detect_from_osc11) ||
BG_COLOR="$FALLBACK_COLOR"

# --- Compute adaptive flash color ---
# Parse #RRGGBB into decimal components
hex_to_dec() { printf '%d' "0x$1"; }

r=$(hex_to_dec "${BG_COLOR:1:2}")
g=$(hex_to_dec "${BG_COLOR:3:2}")
b=$(hex_to_dec "${BG_COLOR:5:2}")

# Perceived luminance (ITU-R BT.601)
lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))

# Dark theme → lighten; light theme → darken
if [ "$lum" -lt 128 ]; then
  # Lighten: add SHIFT, clamp to 255
  fr=$(( r + SHIFT )); [ "$fr" -gt 255 ] && fr=255
  fg=$(( g + SHIFT )); [ "$fg" -gt 255 ] && fg=255
  fb=$(( b + SHIFT )); [ "$fb" -gt 255 ] && fb=255
else
  # Darken: subtract SHIFT, clamp to 0
  fr=$(( r - SHIFT )); [ "$fr" -lt 0 ] && fr=0
  fg=$(( g - SHIFT )); [ "$fg" -lt 0 ] && fg=0
  fb=$(( b - SHIFT )); [ "$fb" -lt 0 ] && fb=0
fi

# Format as #RRGGBB
FLASH_COLOR=$(printf '#%02x%02x%02x' "$fr" "$fg" "$fb")

debug_log "$1" "count=$COUNT bg=$BG_COLOR flash=$FLASH_COLOR"

# --- Pulse loop ---
for (( i = 0; i < COUNT; i++ )); do
  # Set terminal bg to flash color
  printf '\033]11;%s\a' "$FLASH_COLOR" > "$TTY_DEV" 2>/dev/null
  sleep "$PULSE_DURATION"
  # Restore original bg
  printf '\033]11;%s\a' "$BG_COLOR" > "$TTY_DEV" 2>/dev/null
  # Gap between pulses (skip after last)
  if (( i < COUNT - 1 )); then
    sleep "$PULSE_GAP"
  fi
done

exit 0
