# ⚡ Flashy

Visual terminal flash notifications for Claude Code.

When Claude finishes a turn, is waiting for your input, or detects you've stepped away, Flashy pulses your terminal's background color — and optionally pings your phone / Apple Watch via [Pushover](https://pushover.net).

| Hook event | Meaning | Pulses |
|------------|---------|:------:|
| `Stop` | Claude finished a turn | 1 |
| `Notification` (`permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`, `agent_completed`) | Claude wants you — approval, idle nudge, MCP input form, subagent update | 2 |
| `TeammateIdle` | An agent-team teammate went idle | 2 |
| `StopFailure` | The turn died on an API error (rate limit, overload) | 3 |

An **Apple Watch / phone push** (optional) is sent on every one of these events when Pushover credentials are configured.

Claude Code decides when to fire `Notification`, so the delay before an idle flash is up to Claude Code, not Flashy.

<p align="center">
  <img src="demo.gif" alt="Flashy demo" width="500">
</p>

## Install

This is a fork of [foundinblank/flashy](https://github.com/foundinblank/flashy) — see [Credits](#credits).

```bash
claude plugin marketplace add jaredevans/flashy
claude plugin install flashy@flashy
```

Then **set `FALLBACK_COLOR` to your terminal's background color** — that one setting is what makes the flash look right, since background auto-detection can't run inside Claude Code (see [How It Works](#how-it-works)). Flashy computes the flash color adaptively from it: lighter for dark themes, darker for light ones.

Run `/test-flashy` to try it out.

## Configuration

Create `~/.config/flashy/config` (or `$XDG_CONFIG_HOME/flashy/config`) to customize. See [`config.default`](config.default) for all options with descriptions.

Quick start:

```bash
cp /path/to/flashy/config.default ~/.config/flashy/config
# Edit to taste
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `ENABLED` | `true` | Set `false` to disable without uninstalling |
| `STOP_PULSES` | `1` | Pulse count for Stop events |
| `NOTIFICATION_PULSES` | `2` | Pulse count for Notification events |
| `WAITING_PULSES` | `2` | Pulse count for the `waiting` label — unused unless you re-add a `PreToolUse` hook |
| `ERROR_PULSES` | `3` | Pulse count for StopFailure (API error) |
| `IDLE_PULSES` | `2` | Pulse count for TeammateIdle |
| `PULSE_DURATION` | `0.22` | Seconds each pulse is visible |
| `PULSE_GAP` | `0.1` | Seconds between consecutive pulses |
| `SHIFT` | `50` | RGB shift intensity (0-255). Higher = more visible |
| `FALLBACK_COLOR` | `#1a1b26` | **Set this.** Inside Claude Code it's the primary bg source, not a fallback — see below |
| `FLASHY_DEBUG` | `false` | Trace hook firing to `~/.config/flashy/debug.log` |
| `BG_COLOR_FILE` | *(empty)* | Per-TTY bg color file pattern. Use `{tty}` placeholder |
| `PUSHOVER_ENABLED` | `true` | Set `false` to skip Pushover even if creds are set |
| `PUSHOVER_USER_KEY` | *(empty)* | Your Pushover user key — leave empty to disable pushes |
| `PUSHOVER_APP_TOKEN` | *(empty)* | Your Pushover application API token |
| `PUSHOVER_TITLE` | `Claude Code` | Push notification title |
| `PUSHOVER_STOP_MESSAGE` | `Claude finished a turn` | Body for Stop events |
| `PUSHOVER_NOTIFICATION_MESSAGE` | `Claude needs your attention` | Body for Notification events |
| `PUSHOVER_WAITING_MESSAGE` | `Claude is waiting for your input` | Body for the `waiting` label — unused unless you re-add a `PreToolUse` hook |
| `PUSHOVER_ERROR_MESSAGE` | `Claude hit an error and stopped` | Body for StopFailure events |
| `PUSHOVER_IDLE_MESSAGE` | `A Claude teammate went idle` | Body for TeammateIdle events |
| `PUSHOVER_PRIORITY` | `0` | Pushover priority: `-2` (silent) … `0` (default) … `2` (emergency) |
| `PUSHOVER_SOUND` | *(empty)* | Pushover [sound name](https://pushover.net/api#sounds); empty = user default |
| `PUSHOVER_TIMEOUT` | `5` | Max seconds to wait on the Pushover API |

## Pausing Pushover on the fly

The terminal flash always runs, but you can silence the Apple Watch / phone push at any time without editing config:

```bash
touch ~/.config/flashy/pushover-disabled   # mute pushes
rm   ~/.config/flashy/pushover-disabled    # unmute
```

This is the path to mention if you'd like to ask Claude to toggle pushes mid-session — e.g. "mute pushover" / "unmute pushover".

## Apple Watch / Phone Notifications

Flashy can send a push to your phone (and Apple Watch) on every event in the table above using [Pushover](https://pushover.net) — handy when you've stepped away from the terminal.

1. Create a Pushover account and install the iOS app (one-time $5 purchase).
2. From the Pushover dashboard, grab your **User Key** and create an **Application** to get an **API Token**.
3. Add them to `~/.config/flashy/config`:

   ```bash
   PUSHOVER_USER_KEY="your-user-key"
   PUSHOVER_APP_TOKEN="your-app-token"
   ```

4. Test it:

   ```bash
   ./hooks/apple-watch-notify.sh stop
   ```

The script silently no-ops if either key is unset, `curl` is missing, or `PUSHOVER_ENABLED=false` — it never blocks Claude Code. The network call is backgrounded with a `PUSHOVER_TIMEOUT` cap (default 5s).

## Terminal Compatibility

**The auto-detect column applies only when you run `flash.sh` directly from a shell.** Under Claude Code the OSC 11 query is skipped for every terminal in this table, so `FALLBACK_COLOR` is always what gets used — see [How It Works](#how-it-works). The Flash column is the one that matters day to day.

| Terminal | Flash | Auto-detect (direct invocation only) | Notes |
|----------|:-----:|:------------------------------------:|-------|
| Ghostty | ✅ | ✅ | Verified: OSC 11 set works with both `BEL` and `ST` terminators |
| iTerm2 | ✅ | ✅ | Full support |
| Kitty | ✅ | ✅ | Full support |
| WezTerm | ✅ | ✅ | Full support |
| Alacritty | ✅ | ✅ | Full support |
| foot | ✅ | ✅ | Full support |
| tmux | ✅ | ⚠️ | Needs `allow-passthrough on` for auto-detect |
| VS Code | ✅ | ❌ | Set `FALLBACK_COLOR` in config |
| Terminal.app | ❌ | ❌ | Not supported (no OSC 11) |

## Troubleshooting

**I don't see any flash**
- Check the compatibility table above. Terminal.app isn't supported.
- Try setting `FALLBACK_COLOR` in your config to your terminal's actual background color. If it already equals your background, a "flash" that only restores the same color is invisible.
- Set `FLASHY_DEBUG=true` and check `~/.config/flashy/debug.log`. A line per event means the hook fired; `tty_dev=NONE` means no writable terminal was found; no lines at all means the hook never fired (matcher or registration problem, not a flash problem).

**Flash color doesn't restore properly**
- Set `FALLBACK_COLOR` to your terminal's background color, or use `BG_COLOR_FILE` if you have a multi-theme setup.

**I edited `hooks/hooks.json` and nothing changed**

Run `/reload-plugins`. Claude Code takes a snapshot of hook *registration* when a session starts, so adding, removing, or re-matching an event has no effect until you reload or restart. Script *contents* are not snapshotted — edits to `flash.sh` or `apple-watch-notify.sh` take effect on the very next event, which is what makes this asymmetry so confusing to debug.

The reload prints a hook count (`Reloaded: … 13 hooks …`). Each event block contributes two hooks (flash + push), so the count moving by 2 per block you added or removed confirms the new registration took.

**Claude shows a hook error**
- Verify the script is executable: `chmod +x /path/to/flashy/hooks/flash.sh`
- Run it manually to check for errors: `./hooks/flash.sh stop`

**Double flashes**
- If you previously had manual Stop/Notification hooks in `~/.claude/settings.json` calling a flash script, remove those entries. Flashy replaces them.
- Flashy previously hooked `PreToolUse` for `AskUserQuestion`/`ExitPlanMode`. Both were measured double-firing: one flash as the prompt appeared, then another ~6s later from `Notification`. That block was removed, so questions and plan approvals now notify once, via `Notification` only. To trade the duplicate back for a faster signal, re-add a `PreToolUse` block calling `flash.sh waiting` — the scripts still support the `waiting` label.
- Note that one `Notification` produces `NOTIFICATION_PULSES` pulses (default 2). Two pulses in quick succession are one event, not a duplicate; two flashes seconds apart are two events.
- **Unverified, plausible:** an API error may emit both `StopFailure` and `Stop`.

**Pushover notifications never arrive**
- Confirm both `PUSHOVER_USER_KEY` and `PUSHOVER_APP_TOKEN` are set in `~/.config/flashy/config`.
- Run `./hooks/apple-watch-notify.sh stop` directly — if it returns instantly with no push, run the curl in the foreground to see the API response:
  ```bash
  curl --form-string "token=$PUSHOVER_APP_TOKEN" \
       --form-string "user=$PUSHOVER_USER_KEY" \
       --form-string "message=test" \
       https://api.pushover.net/1/messages.json
  ```
- Make sure `curl` is installed and the Pushover iOS app is signed in.

## How It Works

1. Claude Code fires one of the hook events above; `hooks.json` maps it to a label (`stop`, `notification`, `waiting`, `error`, `idle`) passed as `$1`
2. `flash.sh` resolves a terminal to draw on. **Claude Code runs hooks detached from the controlling terminal**, so `/dev/tty` cannot be opened; the script walks up the process tree to the nearest ancestor with a writable TTY device (e.g. `/dev/ttys000`). The immediate parent is not enough — Claude Code spawns the hook through an intermediate shell that is itself detached and reports tty `?`, so the real terminal sits one hop further up
3. `flash.sh` loads config from `~/.config/flashy/config` (if it exists)
4. Detects your terminal's current background color via:
   - Per-TTY color file (`BG_COLOR_FILE`, if configured)
   - OSC 11 terminal query — **skipped when running under Claude Code.** Reading the reply would mean reading from a terminal the hook doesn't own, racing the Claude Code TUI for your keystrokes. Auto-detect only runs when `flash.sh` is invoked directly from a shell
   - `FALLBACK_COLOR` — which is therefore the effective source inside Claude Code
5. Computes perceived luminance — dark themes get a lighter flash, light themes get a darker flash
6. Pulses: sets bg → flash color, sleeps, restores original bg

Because step 4 lands on `FALLBACK_COLOR` in practice, setting it to your real terminal background is the difference between a clean pulse and a background that drifts to the wrong color.

## Credits

Flashy was created by **Adam Stone** ([foundinblank/flashy](https://github.com/foundinblank/flashy)) — the original plugin, the adaptive luminance-based flash color, the OSC 11 detection cascade, and the design this fork is built on.

This fork adds Pushover notifications for phone and Apple Watch, expands hook coverage beyond `Stop`/`Notification`, and fixes the terminal write path under Claude Code. Install instructions above point here because upstream doesn't carry those changes yet.

## License

MIT License - see LICENSE file for details