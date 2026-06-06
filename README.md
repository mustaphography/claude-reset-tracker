# Claude Reset Tracker

A tiny macOS menu bar app that shows the **exact clock time** of your next Claude 5‑hour usage reset — and tints it by your **real usage**. Glance up, see `5:00 AM` in green/yellow/red. That's it.

No countdown to do math on, no notifications, no telemetry. It reads your real usage straight from Anthropic's own usage endpoint (the same way the [Nimbalyst](https://github.com/Nimbalyst/nimbalyst) editor does).

## Why it exists

Claude's 5‑hour rate window opens with your first message and resets 5 hours later. Knowing the **clock time** of the reset ("11:00 PM") is more useful than a moving "1h 47m left," and a quick color tells you how much of your limit you've burned without opening anything.

## Install

Requires macOS 13 (Ventura) or newer, the Swift toolchain (ships with Xcode or Command Line Tools), and a logged‑in Claude Code (`claude`).

```bash
git clone https://github.com/mustaphography/claude-reset-tracker.git
cd claude-reset-tracker
./build.sh --install
```

That compiles the app, packages it as `Claude Reset Tracker.app`, copies it to `/Applications`, and launches it. Look for the colored time in your menu bar.

**On first launch macOS shows a Keychain prompt** — *"…wants to use the confidential information stored in 'Claude Code‑credentials'."* Click **Always Allow**. That's the app reading your Claude Code login token to ask Anthropic for your usage (see [Privacy](#privacy--security)). One‑time click.

To launch on login: System Settings → General → Login Items → add `Claude Reset Tracker`.

## How it works

The menu bar shows your next reset time, colored by how much of the 5‑hour limit you've used:

| Usage | Color |
| --- | --- |
| 0–49% | 🟢 green |
| 50–79% | 🟡 yellow |
| 80–100% | 🔴 red |
| unknown (offline / logged out) | gray |

Both the time and the percentage are **real, authoritative values** from Anthropic — not guesses. The app:

1. Reads your Claude Code OAuth token from the macOS Keychain (item `Claude Code-credentials`).
2. Calls `GET https://api.anthropic.com/api/oauth/usage` with that token (headers: `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`).
3. Reads `five_hour.utilization` (your usage %) and `five_hour.resets_at` (the exact reset instant), plus `seven_day` for the weekly figure.
4. Re‑checks every 5 minutes, and every time you open the popover.

This is the same approach the open‑source Nimbalyst editor uses, including the 50% / 80% color thresholds.

### Offline fallback

If you're offline or your login has expired, the app falls back to **reconstructing** the reset from your local transcripts in `~/.claude/projects/` (or `$CLAUDE_CONFIG_DIR/projects`): it finds your first prompt of the current window and computes first‑message + 5h, **rounded up to the top of the UTC hour** (the reset can only round up — rounding down would hand out free quota). In this mode the time still shows, in gray, but the usage color is unavailable.

## Privacy & security

This app handles your Claude credentials, so here's exactly what it does — all of it is in [`UsageService.swift`](Sources/ClaudeResetTracker/UsageService.swift), ~100 lines you can read:

- It reads the OAuth token from the Keychain item **Claude Code created** (`Claude Code-credentials`), via `/usr/bin/security`.
- It sends that token to **one place only: `https://api.anthropic.com/api/oauth/usage`** — Anthropic's official usage endpoint.
- It **never writes the token to disk, never logs it, and never sends it anywhere else.** No analytics, no third‑party servers, no network calls besides that one Anthropic endpoint.
- The macOS Keychain prompt on first launch is macOS asking *you* to authorize this access. You can revoke it any time in **Keychain Access**.

## States

| What you see | What it means |
| --- | --- |
| **Colored time (e.g. `5:00 AM`)** | Active window. Color = real 5‑hour usage. Click for the exact % and weekly usage. |
| **Gray time** | Usage couldn't be fetched (offline / transient) — the time is from the transcript fallback. |
| **Usage unavailable** | Claude Code login expired. Run `claude`, sign in, then click Refresh. |
| **—** | No active window and nothing to reconstruct. Send a message in Claude Code. |

## Limitations

- **Account‑wide and accurate.** Because the numbers come from Anthropic's account‑level endpoint, they reflect your real usage across machines and clients — not just this Mac. (The old transcript‑only approach couldn't do this; the API can.)
- **Needs a logged‑in Claude Code.** The token comes from Claude Code's Keychain item. No Claude Code login → no usage (offline fallback shows the reconstructed time in gray).
- **Ad‑hoc signed.** On first launch macOS may say "from an unidentified developer." Right‑click the app → Open → Open. After that it launches normally. (Because it's ad‑hoc signed, the Keychain "Always Allow" is tied to `/usr/bin/security`, so it persists across rebuilds.)

## Project layout

```
claude-reset-tracker/
├── Package.swift
├── Sources/ClaudeResetTracker/
│   ├── ClaudeResetTrackerApp.swift   # @main, MenuBarExtra wiring
│   ├── SessionTracker.swift          # state, API + transcript fallback, refresh loop
│   ├── UsageService.swift            # Keychain read + Anthropic usage API
│   ├── MenuBarIcon.swift             # colored-time rendering + thresholds
│   └── MenuBarView.swift             # the small popover UI
├── build.sh                          # SPM build + .app bundle wrapper
├── LICENSE
└── README.md
```

Pure Swift, SwiftUI `MenuBarExtra`, no external dependencies. The release binary is around 200 KB.

## License

MIT. See [LICENSE](LICENSE).
