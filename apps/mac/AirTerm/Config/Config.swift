import Foundation

enum CursorStyle: String {
    case underline
    case block
    case bar
}

/// User-tunable terminal settings, resolved from `~/.config/airterm/config.toml`.
/// Every field has a default so a missing / partial file is always valid.
struct Config: Equatable {
    struct Font: Equatable {
        /// PostScript name. The bundled JetBrainsMono Nerd Font Mono is registered
        /// at launch via `BundledFonts.registerAll()`, so this resolves with no
        /// system install. Loader falls back through Menlo if the name is missing.
        var family: String = "JetBrainsMonoNFM-Regular"
        var size: Double = 14
    }

    struct ThemeRef: Equatable {
        var name: String = "catppuccin-mocha"
        /// Optional pair for auto-follow macOS Appearance. If both are set,
        /// `name` is ignored and the resolver picks based on system dark mode.
        var light: String? = nil
        var dark: String? = nil
    }

    struct Cursor: Equatable {
        var style: CursorStyle = .underline
    }

    struct Window: Equatable {
        var padding: Double = 2     // border/inset in points
        var opacity: Double = 1.0   // window-level alphaValue, 0..1
    }

    struct Shell: Equatable {
        /// When true, AirTerm hands zsh PTYs a ZDOTDIR pointing at a shim
        /// .zshrc that sources the user's real zshrc and layers airprompt
        /// hooks on top. The shim itself yields to starship / p10k /
        /// oh-my-zsh setups so existing prompts win — this flag is
        /// effectively "lay airprompt down when nobody else owns PROMPT".
        var injectPrompt: Bool = true
    }

    struct Chrome: Equatable {
        /// Name of the active ChromeTheme. When set, ConfigStore applies
        /// the matching prompt preset + colour theme on every config load.
        /// Leave nil to opt out and configure prompt / theme individually.
        var preset: String? = nil
    }

    var font = Font()
    var theme = ThemeRef()
    var cursor = Cursor()
    var window = Window()
    var shell = Shell()
    var chrome = Chrome()

    static let `default` = Config()

    /// Canonical user config location.
    static var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/airterm/config.toml")
    }

    /// Sample file shipped to the user the first time the app runs.
    static let sampleContent = """
    # AirTerm config. Edits reload live — no restart needed.

    [font]
    # JetBrainsMono Nerd Font Mono is bundled and auto-registered. Use this
    # PostScript name for full Nerd Font icon coverage (powerline, dev icons,
    # etc.) — required by airprompt-rendered prompts and the status bar.
    # Plain "JetBrainsMono-Regular" also works (no nerd icons), as does any
    # PostScript name installed on your system.
    family = "JetBrainsMonoNFM-Regular"
    size = 14

    [theme]
    # built-ins (dark):  catppuccin-mocha, tokyo-night, dracula, solarized-dark,
    #                    gruvbox-dark, nord, rose-pine, one-dark
    # built-ins (light): catppuccin-latte, tokyo-night-day, rose-pine-dawn,
    #                    gruvbox-light, one-light, solarized-light
    name = "catppuccin-mocha"
    # Auto-follow macOS Appearance: set both, `name` is ignored.
    # light = "catppuccin-latte"
    # dark  = "catppuccin-mocha"

    [cursor]
    # underline | block | bar
    style = "underline"

    [window]
    padding = 2
    opacity = 1.0

    [shell]
    # When true, zsh PTYs get a Starship-grade prompt rendered by airprompt
    # — without editing your ~/.zshrc. Set to false to keep your current
    # prompt setup untouched. Users with starship / p10k / oh-my-zsh
    # already configured will keep their existing prompt either way.
    inject_prompt = true

    [chrome]
    # Optional one-shot bundle: applies a matching prompt preset + colour
    # theme together on every config reload. Leave commented out to
    # configure [theme] and prompt.toml individually.
    #
    # built-in chrome presets:
    #   pastel-powerline, tokyo-night, gruvbox-rainbow, jetpack, minimal
    #
    # preset = "pastel-powerline"
    """

    static func load(from url: URL = Config.userConfigURL) -> Config {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .default
        }
        do {
            let dict = try TOML.parse(text)
            return apply(dict)
        } catch {
            DebugLog.log("Config parse error: \(error); falling back to defaults")
            return .default
        }
    }

    private static func apply(_ dict: [String: Any]) -> Config {
        var config = Config.default
        if let font = dict["font"] as? [String: Any] {
            if let f = font["family"] as? String { config.font.family = f }
            if let s = font["size"] as? Double { config.font.size = s }
            if let s = font["size"] as? Int { config.font.size = Double(s) }
        }
        if let theme = dict["theme"] as? [String: Any] {
            if let n = theme["name"] as? String { config.theme.name = n }
            if let l = theme["light"] as? String { config.theme.light = l }
            if let d = theme["dark"] as? String { config.theme.dark = d }
        }
        if let cursor = dict["cursor"] as? [String: Any] {
            if let s = cursor["style"] as? String, let style = CursorStyle(rawValue: s) {
                config.cursor.style = style
            }
        }
        if let window = dict["window"] as? [String: Any] {
            if let p = window["padding"] as? Double { config.window.padding = p }
            if let p = window["padding"] as? Int { config.window.padding = Double(p) }
            if let o = window["opacity"] as? Double { config.window.opacity = o }
            if let o = window["opacity"] as? Int { config.window.opacity = Double(o) }
        }
        if let shell = dict["shell"] as? [String: Any] {
            if let inject = shell["inject_prompt"] as? Bool { config.shell.injectPrompt = inject }
        }
        if let chrome = dict["chrome"] as? [String: Any] {
            if let preset = chrome["preset"] as? String, !preset.isEmpty {
                config.chrome.preset = preset
            }
        }
        return config
    }

    /// Writes a sample config to disk if it doesn't exist yet. Used on first
    /// launch so a user can discover every tunable by reading the file.
    static func seedIfMissing(at url: URL = Config.userConfigURL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? sampleContent.write(to: url, atomically: true, encoding: .utf8)
    }
}
