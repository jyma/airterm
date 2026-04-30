import AppKit
import Foundation

/// Process-wide config holder. Owns the current `Config` + `Theme`, loads from
/// disk on startup, and watches the config file via a DispatchSource so live
/// edits push through to observers without a restart.
///
/// Resolves the "active" theme through three sources, in priority order:
/// 1. `manualOverride` — user picked a theme via menu / shortcut (session only)
/// 2. `config.theme.light` + `config.theme.dark` — auto-follow macOS Appearance
/// 3. `config.theme.name` — single fixed theme
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: Config
    private(set) var theme: Theme
    private var observers: [UUID: (Config, Theme) -> Void] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "airterm.config.store", qos: .userInitiated)
    /// Session-only override from menu / shortcut. Cleared on config reload
    /// so the TOML remains authoritative after the user edits it.
    private var manualOverride: String?
    private var appearanceObserver: NSObjectProtocol?
    /// The last `chrome.preset` value we applied. Tracking it prevents the
    /// reload path from overwriting the user's prompt.toml on every config
    /// save when nothing about the chrome bundle actually changed.
    private var lastAppliedChromePreset: String?

    private init() {
        Config.seedIfMissing()
        let loaded = Config.load()
        self.config = loaded
        self.theme = Theme.named(Self.resolveThemeName(config: loaded, override: nil))
        observeSystemAppearance()
        applyChromePresetIfNeeded(preset: loaded.chrome.preset)
    }

    /// Start watching the config file. Safe to call multiple times; subsequent
    /// calls reinstall the watcher on the current file descriptor.
    func startWatching(url: URL = Config.userConfigURL) {
        watcher?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            DebugLog.log("ConfigStore: failed to open \(url.path) for watch")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let newConfig = Config.load(from: url)
            DispatchQueue.main.async {
                // A fresh TOML load means the user intentionally re-stated
                // their choice; drop any in-memory override.
                self.manualOverride = nil
                self.config = newConfig
                // Apply chrome.preset BEFORE recomputeTheme so the chrome
                // theme's colour choice wins over any stale [theme] hint.
                self.applyChromePresetIfNeeded(preset: newConfig.chrome.preset)
                self.recomputeTheme()
                // Re-install watcher because editors often replace files
                // atomically, which invalidates the original fd.
                self.startWatching(url: url)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.watcher = source
    }

    @discardableResult
    func subscribe(_ observer: @escaping (Config, Theme) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(config, theme)
        return token
    }

    func unsubscribe(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    /// In-memory theme switch (not persisted). Kept separate from disk-backed
    /// reload so UI shortcuts feel instant; the user's TOML remains the
    /// source of truth on next launch / next config edit.
    func setTheme(named name: String) {
        manualOverride = name
        recomputeTheme()
    }

    /// Transient ChromeTheme switch from the command palette. Copies the
    /// matching prompt preset over the user's prompt.toml and switches the
    /// in-memory colour theme. Doesn't write the chrome.preset back to
    /// config.toml — users who want persistence add `[chrome] preset = …`
    /// themselves so their TOML stays declarative.
    func applyChromeTheme(_ chrome: ChromeTheme) {
        chrome.apply()
        lastAppliedChromePreset = chrome.name
    }

    /// Idempotent helper used on every load: only fires when the config-
    /// declared preset name actually changed since the last apply, so live
    /// edits to unrelated keys never overwrite the user's prompt.toml.
    private func applyChromePresetIfNeeded(preset: String?) {
        guard let name = preset, name != lastAppliedChromePreset else { return }
        guard let theme = ChromeTheme.named(name) else {
            DebugLog.log("ConfigStore: unknown chrome.preset \(name)")
            return
        }
        theme.apply()
        lastAppliedChromePreset = name
    }

    /// Cycle forward (or backward) through the built-in themes.
    func cycleTheme(forward: Bool = true) {
        let names = Theme.builtinNames
        guard !names.isEmpty else { return }
        let current = names.firstIndex(of: theme.name) ?? 0
        let next = forward
            ? (current + 1) % names.count
            : (current + names.count - 1) % names.count
        setTheme(named: names[next])
    }

    // MARK: - Resolution

    private func recomputeTheme() {
        let name = Self.resolveThemeName(config: config, override: manualOverride)
        let resolved = Theme.named(name)
        if resolved.name != theme.name {
            theme = resolved
        }
        // Always broadcast — observers may care about non-theme config changes
        // (font, opacity, cursor style, padding).
        for observer in observers.values {
            observer(config, theme)
        }
    }

    private static func resolveThemeName(config: Config, override: String?) -> String {
        if let override { return override }
        if let light = config.theme.light, let dark = config.theme.dark {
            return isSystemDark() ? dark : light
        }
        return config.theme.name
    }

    private static func isSystemDark() -> Bool {
        let app = NSApplication.shared
        let match = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua
    }

    private func observeSystemAppearance() {
        // macOS broadcasts this distributed notification whenever the user
        // flips System Settings → Appearance, or when `automatic` crosses
        // sunset. We only need to re-resolve; `effectiveAppearance` will
        // reflect the new state by the time the handler fires.
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recomputeTheme()
        }
    }
}
