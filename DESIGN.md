# Flashy — Terminal Flash Notifications for Claude Code

**Date:** 2026-03-16
**Status:** Approved
**Repo:** `~/git/flashy`

## Overview

Flashy is a Claude Code plugin that provides visual terminal flash notifications. When Claude finishes a turn or detects you've stepped away, it pulses your terminal's background color — a subtle, theme-aware signal that works without sound.

**Target audience:** Any Claude Code user, any terminal emulator that supports OSC 11.

## How It Works

The plugin registers every Claude Code hook event that means "Claude is done, or Claude is blocked on you":

| Hook event | Matcher | Label (`$1`) | Default pulses |
|------------|---------|--------------|:--------------:|
| `Stop` | — | `stop` | 1 |
| `StopFailure` | — | `error` | 3 |
| `Notification` | `permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`, `agent_completed` | `notification` | 2 |
| `TeammateIdle` | — | `idle` | 2 |

The scripts still understand a `waiting` label, but no event maps to it by default — see the double-fire note below.

`PermissionRequest` and `Elicitation` are deliberately **not** hooked: they fire for the same moments as `Notification:permission_prompt` and `Notification:elicitation_dialog`, so hooking both would double-notify. The `Notification` lane is the single source of truth for those two.

The `Notification` matcher also excludes `auth_success`, `elicitation_complete`, and `elicitation_response` — those are informational, not "Claude is waiting."

Each pulse changes the terminal background color briefly (via OSC 11 escape sequence), then restores the original color. The flash color is computed adaptively: dark themes get a lighter flash, light themes get a darker flash.

## Plugin Structure

```
~/git/flashy/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── hooks/
│   ├── hooks.json               # Hook event definitions (see table above)
│   ├── flash.sh                 # Core flash script
│   └── apple-watch-notify.sh    # Optional Pushover push (phone + Apple Watch)
├── config.default               # Documented default config (reference only)
├── README.md                    # Install, config reference, troubleshooting
└── LICENSE                      # MIT
```

No skills, no MCP servers, no external dependencies. Just hooks and one bash script.

## Plugin Metadata

`.claude-plugin/plugin.json`:

```json
{
  "name": "flashy",
  "description": "Visual terminal flash notifications for Claude Code — pulses your terminal background whenever Claude finishes a turn or is waiting on you",
  "version": "0.2.0",
  "author": {
    "name": "Adam Stone"
  },
  "keywords": ["notifications", "terminal", "visual", "flash", "accessibility"]
}
```

## Hook Wiring

`hooks/hooks.json` registers both scripts under each event. Abbreviated — see the file for all five blocks:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/flash.sh\" stop" },
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/apple-watch-notify.sh\" stop" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt|elicitation_dialog|agent_needs_input|agent_completed",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/flash.sh\" notification" },
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/apple-watch-notify.sh\" notification" }
        ]
      }
    ]
  }
}
```

Each script receives a **label** as `$1` — not the raw hook event name — and looks up the corresponding pulse count or push message from config. The indirection matters: several distinct hook events collapse to one label's worth of user-facing behavior, and it keeps all tunables in the config file rather than in hook definitions. Adding an event means adding a `hooks.json` block, not touching the scripts.

Both scripts are attached to every event. The flash always runs; only the push is suppressible (via `PUSHOVER_ENABLED` or the `pushover-disabled` sentinel).

## Configuration

### Runtime Config

Users optionally create `~/.config/flashy/config` (shell-sourceable key=value pairs). If the file doesn't exist, all defaults apply — zero config required.

### Defaults

Defaults are baked into the script itself using bash parameter expansion (`${VAR:-default}`). The script:

1. Sources `~/.config/flashy/config` if it exists (sets any user-configured values)
2. Applies defaults via `${VAR:-default}` for anything the config didn't set
3. Proceeds with the merged values

This order matters: sourcing first, then applying defaults, ensures parameter expansion actually acts as a fallback. The reverse order (defaults then source) would make the defaults dead code.

### Config Reference

`config.default` ships with the plugin as documentation (never read at runtime):

```sh
# Flashy — terminal flash notifications for Claude Code
# Copy to ~/.config/flashy/config (or $XDG_CONFIG_HOME/flashy/config) and edit.
# Any value omitted falls back to the default shown here.

# Set to false to disable flashing without uninstalling
ENABLED=true

# Pulses per event type
STOP_PULSES=1
NOTIFICATION_PULSES=2

# Timing (seconds)
PULSE_DURATION=0.22
PULSE_GAP=0.1

# Color shift intensity (0-255 RGB steps)
# Higher = more visible flash. Lower = subtler.
SHIFT=50

# Fallback background color (used when auto-detect fails and no file found)
# Set this to your terminal's background color if flashes look wrong.
FALLBACK_COLOR="#1a1b26"

# Background color file pattern (advanced — for multi-theme setups)
# If your shell writes the current bg color to a file, set the pattern here.
# Use {tty} as placeholder for the TTY name (e.g., ttys002).
# Example: ~/.terminal-bg-color.{tty}
BG_COLOR_FILE=""
```

## Flash Script Logic

`hooks/flash.sh` — the core of the plugin. Flow:

### 1. Load Config

```sh
#!/bin/bash

# Source user config first (if it exists), then apply defaults for anything unset
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/flashy"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"

STOP_PULSES="${STOP_PULSES:-1}"
NOTIFICATION_PULSES="${NOTIFICATION_PULSES:-2}"
PULSE_DURATION="${PULSE_DURATION:-0.22}"
PULSE_GAP="${PULSE_GAP:-0.1}"
SHIFT="${SHIFT:-50}"
FALLBACK_COLOR="${FALLBACK_COLOR:-#1a1b26}"
BG_COLOR_FILE="${BG_COLOR_FILE:-}"
ENABLED="${ENABLED:-true}"

# Early exit if disabled
[ "$ENABLED" = "false" ] && exit 0
```

### 2. Resolve Event → Pulse Count

```sh
case "$1" in
  stop)         COUNT="$STOP_PULSES" ;;
  notification) COUNT="$NOTIFICATION_PULSES" ;;
  *)            COUNT=1 ;;
esac
```

### 3. Detect Background Color

Three-tier detection with priority:

1. **BG_COLOR_FILE** — if set, resolve `{tty}` placeholder with the current TTY name (via `ps -p $PPID -o tty=`) and read the file. For users with multi-theme setups who write per-TTY bg color files.

2. **OSC 11 query** — send `\033]11;?\a` to the terminal, read back the response. The terminal replies with `rgb:RRRR/GGGG/BBBB` (16-bit hex per channel). Convert to 8-bit `#RRGGBB`. Uses a short read timeout (~0.1s) since not all terminals respond.

3. **FALLBACK_COLOR** — static color from config (default `#1a1b26`).

### 4. Compute Adaptive Flash Color

Measure perceived luminance of the detected background:

```
LUM = (R * 299 + G * 587 + B * 114) / 1000
```

- Dark theme (LUM < 128): lighten by `SHIFT` steps
- Light theme (LUM >= 128): darken by `SHIFT` steps

Clamp to 0-255 range.

### 5. Pulse Loop

```
for each pulse:
  set terminal bg to flash color (OSC 11)
  sleep PULSE_DURATION
  restore terminal bg to original color (OSC 11)
  if not last pulse: sleep PULSE_GAP
```

### 6. Exit

Script must `exit 0` explicitly — without it, the `[` test on the last loop iteration can return exit code 1, causing Claude Code to report a hook error.

## Terminal Resolution (`/dev/tty` is not available in hooks)

**Claude Code runs hooks detached from the controlling terminal.** Opening `/dev/tty` from a hook subprocess fails with `Device not configured`, even though the parent Claude Code process is attached to a real TTY (e.g. `ttys000`) and that device is writable by the child.

This was originally silent and total: every write in `flash.sh` was `printf … > /dev/tty 2>/dev/null`, so the failed open was swallowed and the script exited 0 having drawn nothing. The push notification still fired, which made it look like a rendering or terminal-compatibility problem rather than a plumbing one.

`resolve_tty()` therefore cascades:

1. `/dev/tty` if it opens — direct shell invocation, and we own the terminal
2. `/dev/$(ps -p $PPID -o tty=)` — the parent's device, the Claude Code hook case
3. Neither → no terminal to draw on, exit 0 silently (piped context, CI)

It also records `OWN_TTY`, which gates the OSC 11 *query* below. Writing to a terminal we don't own is safe; **reading from one is not** — a `read` on the parent's TTY races the Claude Code TUI for the user's keystrokes. So auto-detect is disabled in the hook path by design, not by accident, and `FALLBACK_COLOR` becomes the effective background source whenever Flashy runs under Claude Code. That makes `FALLBACK_COLOR` a setting users must actually set, not a last resort.

Diagnosing this class of failure requires distinguishing "hook never fired" from "hook fired, wrote nothing." That is what `FLASHY_DEBUG` exists for; the log records the resolved device per invocation.

## Background Color Auto-Detection (OSC 11 Query)

Only runs when `OWN_TTY=1` — see above. This is the one piece of new logic vs. the existing `flash-terminal.sh`. The technique:

```sh
# Send OSC 11 query and read response with timeout
# Note: reading from /dev/tty in a hook subprocess context may not work
# in all environments. If this fails, we silently fall through to FALLBACK_COLOR.
osc11_query() {
    local response=""
    # Redirect stdin from terminal for reading the response
    exec < /dev/tty 2>/dev/null || return 1
    # Send the query
    printf '\033]11;?\a' > /dev/tty 2>/dev/null
    # Read with short timeout — terminal may not respond
    read -t 0.1 -r response 2>/dev/null || return 1

    # Terminal response is a literal escape sequence:
    #   ESC ] 11 ; rgb:RRRR/GGGG/BBBB ESC \    (ST terminator)
    #   ESC ] 11 ; rgb:RRRR/GGGG/BBBB BEL      (BEL terminator)
    # where RRRR/GGGG/BBBB are 16-bit hex values per channel.
    #
    # Extract the rgb: portion using bash string manipulation:
    local rgb="${response#*rgb:}"       # strip everything before "rgb:"
    rgb="${rgb%%[^0-9a-fA-F/]*}"        # strip everything after the hex/slash chars

    # Expect format: RRRR/GGGG/BBBB (4 hex digits per channel, slash-separated)
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
```

**Important caveats:**

- `/dev/tty` read behavior in hook subprocesses is not guaranteed. The existing `flash-terminal.sh` uses `/dev/tty` for *writing* (which works), but *reading* the terminal response is different. If the query fails for any reason, we silently fall through to `FALLBACK_COLOR`. This is why the three-tier detection exists — the OSC query is best-effort.
- Some terminals respond with BEL (`\a`, 0x07) as the terminator, others with ST (`ESC \`, 0x1B 0x5C). The `read` captures everything as a raw string; our parsing strips non-hex characters from the end, so both terminators are handled.
- The `read -t 0.1` timeout is deliberately short. If the terminal doesn't support the query, we don't want to block the hook for long.

**Compatibility:**
- Works: iTerm2, Kitty, WezTerm, Ghostty, Alacritty, foot, xterm
- Partial: tmux (works if `allow-passthrough` is enabled)
- Doesn't work: VS Code integrated terminal, some older terminal emulators

Users on unsupported terminals set `FALLBACK_COLOR` in their config.

## Terminal Compatibility

| Terminal | OSC 11 Query | OSC 11 Set BG | Notes |
|----------|:---:|:---:|-------|
| Ghostty | Yes | Yes | Full support |
| iTerm2 | Yes | Yes | Full support |
| Kitty | Yes | Yes | Full support |
| WezTerm | Yes | Yes | Full support |
| Alacritty | Yes | Yes | Full support |
| foot | Yes | Yes | Full support |
| tmux | Maybe | Yes | Needs `allow-passthrough on` for query |
| VS Code terminal | No | Yes | Flash works, auto-detect doesn't — use FALLBACK_COLOR |
| Terminal.app | No | No | Not supported |

## README Outline

1. **What it does** — 2-sentence description + visual description of the effect
2. **Install** — `claude plugin add ~/git/flashy` (local path)
3. **Configuration** — copy `config.default`, explain each option
4. **Terminal compatibility** — table above
5. **Troubleshooting** — common issues:
   - "I don't see any flash" → check terminal compatibility, try setting FALLBACK_COLOR
   - "Flash color doesn't restore" → set BG_COLOR_FILE or FALLBACK_COLOR
   - "Hook error in Claude" → verify script is executable, check `exit 0`
6. **How it works** — brief technical explanation for the curious

## Design Decisions

- **No dependencies**: pure bash, no jq/python/node. Runs everywhere.
- **No skills**: zero context token overhead. The plugin is invisible during normal use.
- **Shell-sourceable config**: natural for a bash plugin, no JSON parsing gymnastics.
- **Adaptive flash color**: computed from actual background, not a fixed color. Works with any theme without configuration.
- **XDG config path**: `${XDG_CONFIG_HOME:-$HOME/.config}/flashy/config` — respects XDG if set, falls back to `~/.config/`.
- **`exit 0`**: hard-won lesson — bash loop exit codes can trip up Claude Code's hook error detection.
- **ENABLED toggle**: simple on/off switch for debugging or temporary silence without uninstalling.

## Migration Note

If you previously had manual Stop/Notification hooks in `~/.claude/settings.json` calling a flash script (e.g., `flash-terminal.sh`), remove those entries after installing Flashy — otherwise both will fire and you'll get double flashes. Flashy coexists fine with other plugins that use these hooks for different purposes (e.g., sound notifications).

Some overlaps are internal to Flashy, because whether both events fire is up to Claude Code.

**Measured** (Claude Code 2.1.220, two independent reproductions):

```
18:04:56 [waiting]       PreToolUse:AskUserQuestion
18:05:02 [notification]  Notification, same AskUserQuestion — ~6s later
```

Every `AskUserQuestion` produced two flashes and two Pushover pushes.

De-duplicating in code was not an option: the two hook invocations are independent processes with no shared state, so suppression would need a lockfile or timestamp on disk — real complexity for a cosmetic win. The `PreToolUse` block was removed instead. `Notification` covers the same moment ~6s later, and one late notification beats two prompt ones.

The cost is `ExitPlanMode`, which the same block covered. Plan approval is assumed to surface as `Notification:permission_prompt` — **unverified**. If plan mode turns out to notify nothing, restore a `PreToolUse` block matched to `ExitPlanMode` alone; that regains coverage without reintroducing the `AskUserQuestion` duplicate.

**Suspected but unverified:** an API-error turn end emitting both `StopFailure` and `Stop`.
