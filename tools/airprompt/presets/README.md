# airprompt presets

Five prompt visual styles, hand-tuned for AirTerm. Each is a complete
`prompt.toml` you can drop straight into `~/.config/airterm/`.

| preset | feel | matches colour theme |
|---|---|---|
| `pastel-powerline.toml` | dense bold colour blocks, full Nerd Font icons | any dark theme |
| `tokyo-night.toml` | low-saturation purple/blue, bracketed segments | tokyo-night |
| `gruvbox-rainbow.toml` | warm rainbow per module, includes clock | gruvbox-dark / -light |
| `jetpack.toml` | compact, 🚀 anchor, bold cyan path | any (informal) |
| `minimal.toml` | plain text, no Nerd Font icons, `$` prompt | any (works in non-Nerd-Font terminals) |

## Switch

```bash
cp /Applications/AirTerm.app/Contents/Resources/airprompt-presets/jetpack.toml \
   ~/.config/airterm/prompt.toml
```

The next prompt picks it up — no AirTerm restart needed (airprompt re-reads
the TOML on every prompt render).

## Customize

Copy a preset to `~/.config/airterm/prompt.toml`, then edit. Schema:

```toml
format = ["directory", "git_branch", "git_status", "command_duration", "status"]

[directory]
truncation_length = 3        # keep last N path components
style = "bold cyan"          # space-separated: bold/dim/italic/underline + colour
home_symbol = "~"

[git_branch]
symbol = " "                #  prefix (Nerd Font branch glyph)
style = "bold purple"

[git_status]
modified = "*"
ahead = "⇡"
behind = "⇣"
style = "yellow"

[command_duration]
min_time_ms = 2000           # hide unless previous command took longer
style = "yellow"

[status]
style = "bold red"           # only renders when last exit code != 0

[time]
disabled = true              # set false to show
format = "%H:%M"             # strftime spec
style = "white"

[character]
success = "❯"
error = "❯"
success_style = "green"
error_style = "red"
```

Supported colour names: `black red green yellow blue purple/magenta cyan white`.
Supported attributes: `bold dim italic underline reverse`. An empty `style`
disables ANSI colouring (matches the `minimal` preset).

## Notes

- All presets except `minimal` assume a Nerd Font. AirTerm bundles
  JetBrainsMono Nerd Font Mono and registers it at launch, so this is the
  default in-app. Outside AirTerm (Terminal.app etc.) install a Nerd Font or
  use `minimal`.
- Modules return nothing when there's no data (clean git, fast command,
  zero exit) so the prompt stays compact regardless of preset.
