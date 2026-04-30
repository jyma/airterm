# Built-in Themes — Attribution

AirTerm ships with 14 curated colour themes (8 dark + 6 light). All are used
under permissive open-source licences; hex values are ported faithfully from
each project's official spec.

## Dark

| Theme | Author | License | Upstream |
|---|---|---|---|
| catppuccin-mocha | Catppuccin org | MIT | https://github.com/catppuccin/catppuccin |
| tokyo-night | Enkia (enkia) | MIT | https://github.com/enkia/tokyo-night-vscode-theme |
| dracula | Zeno Rocha / Dracula org | MIT | https://github.com/dracula/dracula-theme |
| solarized-dark | Ethan Schoonover | MIT | https://github.com/altercation/solarized |
| gruvbox-dark | Pavel Pertsev | MIT | https://github.com/morhetz/gruvbox |
| nord | Arctic Ice Studio | MIT | https://github.com/nordtheme/nord |
| rose-pine | Rosé Pine org | MIT | https://github.com/rose-pine/rose-pine-theme |
| one-dark | Atom / GitHub | MIT | https://github.com/atom/atom/tree/master/packages/one-dark-ui |

## Light

| Theme | Author | License | Upstream |
|---|---|---|---|
| catppuccin-latte | Catppuccin org | MIT | https://github.com/catppuccin/catppuccin |
| tokyo-night-day | Enkia (enkia) | MIT | https://github.com/folke/tokyonight.nvim |
| rose-pine-dawn | Rosé Pine org | MIT | https://github.com/rose-pine/rose-pine-theme |
| gruvbox-light | Pavel Pertsev | MIT | https://github.com/morhetz/gruvbox |
| one-light | Atom / GitHub | MIT | https://github.com/atom/atom/tree/master/packages/one-light-ui |
| solarized-light | Ethan Schoonover | MIT | https://github.com/altercation/solarized |

## Using a theme

### Fixed theme

```toml
[theme]
name = "gruvbox-dark"
```

### Auto-follow system Appearance

AirTerm listens to macOS System Settings → Appearance. Set `light` + `dark`
in the same config — the currently-active one is chosen automatically and
swaps live when the system crosses sunset (or you flip the toggle):

```toml
[theme]
light = "catppuccin-latte"
dark  = "catppuccin-mocha"
```

When both `light` and `dark` are set, the `name` field is ignored.

### Menu / shortcut

**View → Theme** — ⌃⌘1 … ⌃⌘8 for the 8 dark themes, ⌃⌘T to cycle through
all 14. Light themes are menu-only. A manual pick stays active for the
session; editing the TOML resets it.

## Porting a theme

Our `Theme` struct (`apps/mac/AirTerm/Config/Theme.swift`) needs:
background, foreground, cursor, selection (RGBA — alpha < 1 for translucent
highlight), accent, plus 8 standard and 8 bright ANSI colours.

Nearly every popular theme publishes these exact values. Grab from the
project's `colors.lua` / `palette.toml` / iTerm2 `.itermcolors` and translate.
For bulk sources, [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
(MIT) catalogues 450+ themes in a consistent format.
