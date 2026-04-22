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
        var family: String = "JetBrainsMono-Regular"
        var size: Double = 14
    }

    struct ThemeRef: Equatable {
        var name: String = "catppuccin-mocha"
    }

    struct Cursor: Equatable {
        var style: CursorStyle = .underline
    }

    struct Window: Equatable {
        var padding: Double = 2     // border/inset in points
        var opacity: Double = 1.0   // window-level alphaValue, 0..1
    }

    var font = Font()
    var theme = ThemeRef()
    var cursor = Cursor()
    var window = Window()

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
    family = "JetBrainsMono-Regular"
    size = 14

    [theme]
    # built-ins: catppuccin-mocha, tokyo-night, dracula, solarized-dark
    name = "catppuccin-mocha"

    [cursor]
    # underline | block | bar
    style = "underline"

    [window]
    padding = 2
    opacity = 1.0
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
