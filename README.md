# Claude Reset Tracker

A tiny macOS menu bar app that tells you the **exact clock time** of your next Claude 5‑hour usage reset. Click the icon, see "Next reset: 8:15 PM". That's it.

No countdown, no notifications, no telemetry, no login — it reads your local Claude Code session files to figure out when your current 5‑hour window started.

## Why it exists

Claude's 5‑hour rate window opens the moment you send your first message and ends exactly 5 hours later. Knowing the **clock time** of the reset is more useful than "you have 1h 47m left" — you can plan around 8:15 PM, you can't plan around a moving countdown.

## Install

Requires macOS 13 (Ventura) or newer and the Swift toolchain (ships with Xcode or Command Line Tools).

```bash
git clone https://github.com/<you>/claude-reset-tracker.git
cd claude-reset-tracker
./build.sh --install
```

That compiles the app, packages it as `Claude Reset Tracker.app`, copies it to `/Applications`, and launches it. Look for the clock icon in your menu bar.

To build without installing:

```bash
./build.sh
open "build/Claude Reset Tracker.app"
```

To launch on login: System Settings → General → Login Items → add `Claude Reset Tracker`.

## How it works

When you send a message in Claude Code, it appends to a JSONL transcript at `~/.claude/projects/<encoded-path>/<session-id>.jsonl`. Each line is one event with an ISO‑8601 `timestamp`. Claude Code knows your exact reset time (it shows "Resets in 2h 23m") but **does not persist it** — it only lives in the API rate‑limit headers in memory. So a standalone app has to reconstruct it from the transcript timestamps.

The app:

1. Walks `~/.claude/projects/` (or `$CLAUDE_CONFIG_DIR/projects`) for `.jsonl` files modified in the last 12 hours.
2. Collects the timestamp of every **real user prompt** — `type: "user"` messages whose content is a typed prompt, excluding tool results and subagent (sidechain) messages.
3. Reconstructs sessions: walking prompts oldest→newest, a new 5‑hour window opens whenever a prompt arrives **5h or more** after the current window started. The most recent window is the active one.
4. Computes the reset as **first‑message‑time + 5h, rounded *up* to the top of the hour**.
5. Re‑checks every 60 seconds, and again every time you click the icon.

### Why round up to the hour?

Claude's 5‑hour windows reset on a clock‑hour boundary. The reset can only be rounded **up**, never down — rounding down would let a new window open before 5 hours elapsed and hand out free quota, which Anthropic doesn't do. So:

```
first message 5:39 PM  →  + 5h = 10:39 PM  →  reset rounds up to 11:00 PM
```

Hour boundaries are anchored to **UTC** (server‑side), and the app rounds in UTC before formatting in your local time. For whole‑hour timezones (most of the world) this is identical to local rounding; for half‑hour offsets like UTC+5:30 (India) or UTC+3:30 (Iran) the UTC anchor is the correct one.

## States

| What you see | What it means |
| --- | --- |
| **Next reset: HH:MM** | Active window. You sent your first message at "Window started …" and reset is 5h after that. |
| **No active window** | Nothing in `~/.claude/projects/` within the last 5h. Send a message in Claude Code to start the timer. |
| Reset time has passed | Auto-refresh hasn't run yet. Click **Refresh** — the next message you send opens a fresh window. |

## Limitations

- **Claude Code only.** It reads local transcripts, so it can't see Claude.ai web/mobile/desktop usage. If your account's window was actually opened by a web session, the reconstructed time can be off. (Most Claude Code users start their window in the terminal, so in practice it's accurate.)
- **One machine's view.** The 5‑hour limit is account‑wide, but the app only sees the transcripts on *this* Mac. If you also use Claude Code on another machine, the earliest first‑message there isn't visible here.
- **Reconstructed, not reported.** Because Claude Code doesn't persist the reset time, this is an inference. It matches Claude's own "Resets in …" in every case tested, but it's derived from timestamps + the rounding rule above, not read from an official field.
- If you wipe `~/.claude/projects/`, the app will correctly show "No active window" until your next message.
- Ad‑hoc signed — on first launch macOS may say "from an unidentified developer". Right‑click the app → Open → Open. After that it launches normally.

## Project layout

```
claude-reset-tracker/
├── Package.swift
├── Sources/ClaudeResetTracker/
│   ├── ClaudeResetTrackerApp.swift   # @main, MenuBarExtra wiring
│   ├── SessionTracker.swift          # window detection + refresh
│   └── MenuBarView.swift             # the small popover UI
├── build.sh                          # SPM build + .app bundle wrapper
├── LICENSE
└── README.md
```

Pure Swift, SwiftUI `MenuBarExtra`, no external dependencies. The release binary is around 200 KB.

## License

MIT. See [LICENSE](LICENSE).
