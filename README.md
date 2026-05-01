# AirTerm

A native macOS terminal you can take over from any browser.

Open a tab on your laptop, head to lunch, keep typing on your phone. AirTerm
ships a Ghostty-class native terminal for the Mac and a PWA mirror for any
browser; pair them once with a QR code and the phone tracks the live shell —
output, input, vim, htop, the lot.

## Features

- **Native macOS terminal** — Metal-rendered grid, 120 fps when the display
  cooperates, JetBrains Mono Nerd Font built in, custom tab bar, command
  palette (⇧⌘P), 14 colour themes, 5 starship-flavoured prompts driven by a
  bundled Rust prompt renderer (`airprompt`).
- **Phone takeover** — scan a QR, get a live mirror in your browser. Soft
  keyboard + a sticky toolbar (Esc / Tab / Ctrl-latch / arrows) so vim / htop
  / Ctrl-C all work from a phone. Add to home screen for a native-feeling PWA.
- **End-to-end encrypted** — Noise IK (Curve25519 + ChaCha20-Poly1305 +
  SHA-256) between Mac and phone. The relay forwards opaque ciphertext and
  cannot read frames, ever. Channel binding lets the user verify the
  connection out of band.
- **Self-healing connection** — a long-lived `ConnectionManager` re-runs the
  Noise handshake whenever the WebSocket drops; the user sees
  `Live → Reconnecting → Live` instead of a frozen mirror.
- **Configurable** — `~/.config/airterm/config.toml`, hot-reloaded. Themes,
  fonts, prompt presets, opacity, padding, cursor style. No GUI settings
  panel; the file is the API.

## Status

This is the v1 development branch. The end-to-end product loop works locally
(pair, mirror, type, reconnect, forget). Ad-hoc signed `.app` builds via the
included scripts; Apple Developer ID signing + notarization is wired but not
yet active (needs maintainer credentials). See `docs/PROGRESS.md` for the
phase-by-phase ledger.

## Architecture

```
                  Apple Silicon / Intel Mac
   ┌────────────────────────────────────────────────────────┐
   │  AirTerm.app                                           │
   │   ├── Metal terminal (Phase 1 + 2.5 chrome)            │
   │   ├── airprompt (Rust, lipo'd universal)               │
   │   ├── PairingService (Noise IK responder)              │
   │   ├── PairingCoordinator (background WS listener)      │
   │   ├── TakeoverSession (30 Hz screen broadcast +        │
   │   │                    inbound input → PTY)            │
   │   └── PairedDevicesWindow (manage / forget)            │
   └─────────────────────────┬──────────────────────────────┘
                             │ WSS
                  ┌──────────▼──────────┐
                  │    Relay server     │  ← Hono + WebSocketServer
                  │ (TypeScript / Fly)  │     opaque payload forwarding,
                  │                     │     pair gate + per-WS rate limit
                  └──────────┬──────────┘
                             │ WSS
   ┌─────────────────────────▼──────────────────────────────┐
   │  Phone PWA  (React 19 + Vite, no xterm.js)             │
   │   ├── PairPage (BarcodeDetector QR + manual fallback)  │
   │   ├── ConnectionManager (auto-rehandshake)             │
   │   ├── TakeoverViewer (DOM grid, per-row diff)          │
   │   └── MobileKeyToolbar (Esc/Tab/Ctrl/arrows)           │
   └────────────────────────────────────────────────────────┘
```

Each frame: `TakeoverFrame` (typed JSON) → `NoiseCipherState.encrypt` →
base64 `EncryptedFrame` → `SequencedMessage` → `RelayEnvelope` → WebSocket.
The relay only sees the envelope. See `packages/protocol/src/` for the
schemas (`signaling.ts`, `takeover.ts`).

## Project layout

```
airterm/
├── apps/
│   ├── mac/                 # macOS app — Swift + AppKit + Metal
│   │   ├── AirTerm/
│   │   ├── scripts/         # bundle.sh, dmg.sh
│   │   └── Package.swift
│   ├── server/              # Relay — Hono + better-sqlite3
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── fly.toml
│   └── web/                 # Phone PWA — React 19 + Vite
│       ├── src/
│       ├── public/          # manifest.webmanifest, icon.svg
│       └── index.html
├── packages/
│   ├── protocol/            # Shared TS types (envelopes, signaling, takeover)
│   └── crypto/              # Noise IK + X25519 + ChaCha20-Poly1305
├── tools/
│   └── airprompt/           # Rust prompt renderer (libgit2 + chrono)
└── docs/                    # PROGRESS.md, ROADMAP.md, etc.
```

## Quick start (development)

Prereqs: macOS 14+, Xcode 15+ (or Command Line Tools for Swift only),
Node 22+, pnpm 10+, Rust + cargo (any stable).

```bash
git clone git@github.com:jyma/airterm.git
cd airterm
pnpm install

# Terminal 1 — relay
pnpm --filter @airterm/server dev          # http://localhost:3000

# Terminal 2 — phone PWA
pnpm --filter @airterm/web dev             # http://localhost:5173

# Terminal 3 — Mac app
AIRTERM_RELAY_URL=http://localhost:3000 \
  bash apps/mac/scripts/bundle.sh
open apps/mac/build/AirTerm.app
```

Mac → File → Pair New Device. Scan from the phone PWA at
`http://localhost:5173/pair`, or paste the JSON shown beneath the QR if the
camera path is unhelpful. The phone routes through `ConnectionManager`,
runs Noise IK, and lands on a live mirror.

## Distribution builds

```bash
# Universal .app (x86_64 + arm64 lipo'd airprompt, swift -c release)
bash apps/mac/scripts/bundle.sh --release

# Wrap into a drag-to-Applications DMG
bash apps/mac/scripts/dmg.sh

# Result: apps/mac/build/AirTerm-0.1.0.dmg
```

A tag-driven GitHub workflow (`.github/workflows/release.yml`) does both on
`v*` tags and publishes the DMG as a release asset.

The relay container builds via `apps/server/Dockerfile` (3-stage, slim
runtime). `apps/server/fly.toml` deploys to fly.io with a persistent volume
for the SQLite store; `fly deploy` from `apps/server/`.

## Tests

```bash
pnpm test                 # 150 tests across protocol / crypto / web / server
pnpm lint                 # eslint
swift build               # in apps/mac/, just to verify the bundle compiles
```

E2E lives in `apps/server/src/__tests__/noise-pair-e2e.test.ts`: spins up a
real Hono + WS server, simulates Mac + Phone with `@airterm/crypto`, and
walks the entire pair → IK → screen frame round trip in ~250 ms.

## Configuration

`~/.config/airterm/config.toml` is created on first launch with every
setting commented. Hot-reloaded; no restart needed. Highlights:

```toml
[font]
family = "JetBrainsMonoNFM-Regular"
size = 14

[theme]
name = "catppuccin-mocha"           # one of 14 built-ins
# light = "catppuccin-latte"         # auto-follow Appearance pair
# dark  = "catppuccin-mocha"

[chrome]
# Optional: bundle prompt + colour theme as one preset.
# preset = "tokyo-night"

[shell]
inject_prompt = true                # use airprompt without touching .zshrc
```

`~/.config/airterm/prompt.toml` controls the bundled `airprompt` renderer.
The command palette ships five starship-style preset writers
(`pastel-powerline` / `tokyo-night` / `gruvbox-rainbow` / `jetpack` /
`minimal`).

## Decisions / non-goals

- **Mac UI:** AppKit primary, SwiftUI deferred to settings windows. Metal
  is non-negotiable for the terminal grid.
- **Phone UI:** Pure React DOM grid. We considered `xterm.js` but the Mac
  parses ANSI to typed cells already; phone just renders.
- **Transport (today):** Noise transport over the WS relay. Latency target
  for v1 is "interactive but not gaming-grade".
- **Transport (next):** WebRTC P2P DataChannel + TURN fallback (coturn).
  SDP/ICE schema already exists; the libwebrtc Swift integration is the
  remaining work.
- **Dotfiles:** AirTerm never modifies the user's `.zshrc` / `.bashrc`. It
  injects prompts via `ZDOTDIR` / `--rcfile` shims and yields cleanly to
  starship / p10k / oh-my-zsh when they're already configured.

## License

MIT. See [LICENSE](LICENSE) for details.
