import Foundation

/// Process-wide config holder. Owns the current `Config` + `Theme`, loads from
/// disk on startup, and watches the config file via a DispatchSource so live
/// edits push through to observers without a restart.
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config: Config
    private(set) var theme: Theme
    private var observers: [UUID: (Config, Theme) -> Void] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "airterm.config.store", qos: .userInitiated)

    private init() {
        Config.seedIfMissing()
        let loaded = Config.load()
        self.config = loaded
        self.theme = Theme.named(loaded.theme.name)
        AnsiPalette.theme = self.theme
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
            let newTheme = Theme.named(newConfig.theme.name)
            DispatchQueue.main.async {
                self.apply(config: newConfig, theme: newTheme)
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

    /// Push the latest state to every observer on the main thread.
    private func apply(config: Config, theme: Theme) {
        guard config != self.config || theme.name != self.theme.name else { return }
        self.config = config
        self.theme = theme
        AnsiPalette.theme = theme
        for observer in observers.values {
            observer(config, theme)
        }
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
}
