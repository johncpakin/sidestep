<div align="center">

<img src="assets/SideStepLogo.png" width="128" alt="Sidestep icon">

# Sidestep

**Every Claude account. One menu bar.**
*See the burn. Switch before it bites.*

<br>

Sidestep is a native macOS menu-bar app for people running more than one Claude account.
It shows live usage for all of them, warns you before a limit hits, and moves Claude Code
between accounts in one click — every open terminal follows, no `/logout`, no `/login`, no restarts.

<br>

![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0071e3)
![Footprint](https://img.shields.io/badge/menu%20bar-native%2C%20no%20Electron-6fbe8e)

</div>

---

The menu bar always shows where you stand:

```
Alexa ▸ 7% · 35%        ← account · running-marker · 5-hour % · weekly %
```

## Install

```bash
curl -fsSL https://sidestep.sh/install | sh
```

Or from source:

```sh
./scripts/build-app.sh --install   # builds and copies Sidestep.app to /Applications
open /Applications/Sidestep.app
```

Requires macOS 14+ and Xcode command-line tools. On first launch, allow notifications when macOS asks — that's how usage warnings reach you.

## The panel

Click the menu-bar item. Each account shows three things per limit — a segment bar, the percentage, and time until reset (hover it for the exact day and time):

```
5H     ████████░░░░░░░░░░░░░  17%   2H 27M     ← 5-hour session limit
7D     ██████████████░░░░░░░  32%   1D 8H      ← 7-day weekly limit
FABLE  ▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░  43%   1D 8H      ← per-model weekly limit, when your plan has one
```

Bars stay neutral below 50%, turn amber at 50%, red at 80% — color only ever means "pay attention."

**Switching accounts** is the vertical shifter on the left edge: one notch per account, a knob parked on the account Claude Code is currently using. Click a notch (or drag the knob) and Claude Code is signed into that account — new terminals immediately, already-running sessions within about 30 seconds, no restarts. Accounts that need a fresh sign-in show a locked notch and a **SIGN IN** button instead.

**Reset timeline** at the bottom: every account's 7-day window on one time axis, filled to its usage, with ticks where each limit resets. When two accounts reset the same day, you see it line up.

Also in the panel:

- **Rename** an account by clicking its name — display-only nicknames.
- **Add account** opens the standard Claude sign-in in your browser (with a paste-the-code fallback if the localhost redirect can't reach the app).
- **Poll interval** picker (1–30 min, default 5) with a running request counter, so you always know how often it calls out.

## Usage warnings

Sidestep notifies you when any account — not just the active one — crosses **80%, 90%, or 95%** of any limit:

> **Alexa at 96%** — 95% threshold crossed on the 5-hour limit · resets Today at 2:09 PM

Each threshold fires once per limit per reset window, even across app restarts; after the reset, the slate is clean. A jump straight from 60% to 96% produces one notification, not three. Warnings arrive within one poll interval of the crossing — shorten the interval on heavy days.

## Knowing when Claude is running

While anything is actively burning a budget, the menu-bar separator becomes `▸` and the next unlit segment of that account's bar blinks. Sidestep detects this two ways:

1. It checks the system process list every 10 seconds for a running `claude` CLI — existence only.
2. It compares usage between polls; if an account's session percentage rose, something is using it (even on another machine).

**Sidestep never reads your conversations.** There is no code in the app that opens chat files — the only inputs are the process list and Anthropic's own usage API.

## How it works

Claude Code keeps its login in the macOS Keychain and re-reads it on every request (with a ~30-second cache). Sidestep switches accounts by writing the chosen account's OAuth tokens into that Keychain item — which is why every open terminal follows along on its next turn. The account being switched away from is saved to Sidestep's store first, so it's one click to come back.

- Credentials live in the Keychain (active account) and `~/Library/Application Support/Sidestep/accounts/` (everyone else), as OAuth token files.
- Usage comes from `api.anthropic.com/api/oauth/usage`; identity from `/api/oauth/profile`; token refresh via `platform.claude.com/v1/oauth/token`.

Because Anthropic invalidates the old token every time one is refreshed, Sidestep is strict about who refreshes what:

1. It identifies the active account by asking the API who owns the Keychain token — never by trusting config files that can lag.
2. It never refreshes the active account itself; Claude Code owns that token.
3. It re-reads stored accounts from disk before refreshing, in case something else got there first.
4. It never writes a token into an account's file without confirming with the API that the token belongs to that account — so signing in with the wrong browser profile just adds *that* account, it can't corrupt another one.

## Troubleshooting

- **A row shows `RE-AUTH`** — that account's stored token is no longer valid. Click **SIGN IN** using a browser signed into *that* account (a private window is easiest).
- **"localhost can't be reached" during sign-in** — the panel is still waiting: click **OPEN PASTE-MODE LINK**, approve in the browser, and paste the `code#state` it shows.
- **`WAITING FOR CLAUDE CODE TO REFRESH`** — the active account's token just expired; run any `claude` prompt and both apps are current again.
- **`EDGE RATE-LIMITED`** — Anthropic throttled a burst of requests; the last good numbers stay on screen and the next poll clears it.
- **Random logouts** — some other tool on your machine is refreshing tokens for the account Claude Code is signed into; each refresh revokes the previous token. Stop that tool or point it at a different account.

## Code map

```
Sources/Sidestep/
  App.swift        menu-bar item + panel window
  Views.swift      the panel
  Shifter.swift    the account shifter
  Timeline.swift   the reset timeline
  Monitor.swift    polling, switching, warnings, activity detection
  OAuth.swift      sign-in, refresh, usage/profile API
  Stores.swift     Keychain + account files
  Notifier.swift   notifications
  Theme.swift      colors, type, shared controls
  Resources/Fonts  IBM Plex (OFL), bundled
```
