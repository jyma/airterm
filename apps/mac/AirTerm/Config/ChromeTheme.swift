import Foundation

/// A "ChromeTheme" bundles the visual decisions that span surfaces — the
/// airprompt prompt preset, the colour theme, and (later) tab/status fine
/// tuning — into a single switchable identity. Applying one is a one-shot
/// that copies the matching prompt.toml into ~/.config/airterm/ and switches
/// the in-memory colour theme. The five built-ins each pair a starship-style
/// prompt with the colour theme it was designed against.
///
/// Persistence model: users can pin their preferred preset by writing
///
///     [chrome]
///     preset = "tokyo-night"
///
/// in `config.toml`. On config load, ConfigStore applies the named preset
/// once. Switching presets at runtime via the command palette is transient —
/// the active config file remains the source of truth across launches.
struct ChromeTheme: Equatable {
    let name: String
    let displayName: String
    let description: String
    let promptPreset: String
    let colorTheme: String

    static let all: [ChromeTheme] = [
        ChromeTheme(
            name: "pastel-powerline",
            displayName: "Pastel Powerline",
            description: "Bold colour blocks · Catppuccin Mocha",
            promptPreset: "pastel-powerline",
            colorTheme: "catppuccin-mocha"
        ),
        ChromeTheme(
            name: "tokyo-night",
            displayName: "Tokyo Night",
            description: "Low-saturation purple/blue · Tokyo Night",
            promptPreset: "tokyo-night",
            colorTheme: "tokyo-night"
        ),
        ChromeTheme(
            name: "gruvbox-rainbow",
            displayName: "Gruvbox Rainbow",
            description: "Warm rainbow per module · Gruvbox Dark",
            promptPreset: "gruvbox-rainbow",
            colorTheme: "gruvbox-dark"
        ),
        ChromeTheme(
            name: "jetpack",
            displayName: "Jetpack",
            description: "Compact, rocket anchor · Dracula",
            promptPreset: "jetpack",
            colorTheme: "dracula"
        ),
        ChromeTheme(
            name: "minimal",
            displayName: "Minimal",
            description: "Plain text, no icons · Nord",
            promptPreset: "minimal",
            colorTheme: "nord"
        ),
    ]

    static func named(_ name: String) -> ChromeTheme? {
        all.first { $0.name == name.lowercased() }
    }

    /// One-shot apply: copy the bundled prompt preset over the user's
    /// `~/.config/airterm/prompt.toml` and switch the in-memory colour
    /// theme. Best-effort — prompt copy failures log but don't abort the
    /// theme switch (so the user still sees a partial change instead of a
    /// silent no-op).
    func apply() {
        applyPromptPreset(promptPreset)
        ConfigStore.shared.setTheme(named: colorTheme)
    }

    private func applyPromptPreset(_ presetName: String) {
        let bundle = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/airprompt-presets")
            .appendingPathComponent("\(presetName).toml")
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            DebugLog.log("ChromeTheme: bundled \(presetName).toml not found")
            return
        }
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/airterm/prompt.toml")
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            let data = try Data(contentsOf: bundle)
            try data.write(to: dest, options: .atomic)
            DebugLog.log("ChromeTheme: applied prompt preset \(presetName)")
        } catch {
            DebugLog.log("ChromeTheme: prompt copy failed: \(error)")
        }
    }
}
