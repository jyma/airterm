import AppKit

/// ⇧⌘P fuzzy command palette — a floating NSPanel with a search field on top
/// and a results table below. Mirrors the VS Code / Sublime / Raycast pattern
/// because users expect "the modern keyboard-first chrome shortcut" to live
/// here. All commands are first-class structs so adding new entries is just
/// `Command.all.append(...)` — no plugin layer, no DSL.
final class CommandPalette: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    /// All commands. Filtered by the search field; index into `filtered` is
    /// what the table renders.
    private var commands: [Command] = []
    private var filtered: [Command] = []
    private var theme: Theme = ConfigStore.shared.theme

    // Keep the launching window so commands act on the right pane / tab.
    private weak var sourceWindow: NSWindow?

    static let shared = CommandPalette()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = ""
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        hidesOnDeactivate = true
        // Close on outside click — common HUD-style behaviour.
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow

        setupContent()
        rebuildCommands()
    }

    // MARK: - Public API

    /// Toggle visibility, anchoring the panel above `window` so it follows
    /// whichever AirTerm window the user invoked it from. Re-presents
    /// fresh-state on every open (search cleared, focus on the field).
    func toggle(from window: NSWindow?) {
        if isVisible {
            orderOut(nil)
            return
        }
        sourceWindow = window
        if let win = window {
            // Centre horizontally in the source window, ~25% from the top.
            let f = win.frame
            let palette = frame
            let x = f.minX + (f.width - palette.width) / 2
            let y = f.maxY - palette.height - f.height * 0.25
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        rebuildCommands()
        searchField.stringValue = ""
        applyFilter("")
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(self?.searchField)
        }
    }

    // MARK: - Setup

    private func setupContent() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.layer?.cornerRadius = 12

        searchField.frame = NSRect(x: 12, y: content.bounds.height - 36, width: content.bounds.width - 24, height: 24)
        searchField.autoresizingMask = [.width, .minYMargin]
        searchField.placeholderString = "Type a command…"
        searchField.delegate = self
        searchField.font = NSFont.systemFont(ofSize: 13)
        content.addSubview(searchField)

        scroll.frame = NSRect(x: 12, y: 12, width: content.bounds.width - 24, height: content.bounds.height - 56)
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        table.headerView = nil
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.rowHeight = 28
        table.allowsMultipleSelection = false
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(runSelected)
        table.target = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)

        scroll.documentView = table
        content.addSubview(scroll)
    }

    private func rebuildCommands() {
        commands = Command.all()
    }

    private func applyFilter(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filtered = commands
        } else {
            filtered = commands.filter { c in
                c.title.lowercased().contains(q) ||
                c.subtitle.lowercased().contains(q)
            }
        }
        table.reloadData()
        if !filtered.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    // MARK: - Key handling

    /// Intercept Up/Down/Return/Esc on the search field so the user can drive
    /// the table without leaving the field — the standard palette UX.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            runSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            orderOut(nil); return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = table.selectedRow
        let next = max(0, min(filtered.count - 1, current + delta))
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    @objc private func runSelected() {
        guard table.selectedRow >= 0, table.selectedRow < filtered.count else { return }
        let cmd = filtered[table.selectedRow]
        let target = sourceWindow
        orderOut(nil)
        // Defer execution one tick so the panel's own dismissal completes
        // before the action (some commands open new windows, which would
        // otherwise inherit our hidesOnDeactivate quirks).
        DispatchQueue.main.async {
            cmd.run(target)
        }
    }

    // MARK: - Table data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? CommandRow)
            ?? CommandRow()
        cell.identifier = identifier
        cell.configure(with: filtered[row], theme: theme)
        return cell
    }
}

/// One row in the palette. Two stacked labels: title (with NF icon) on top,
/// subtitle (key equivalent / description) below.
private final class CommandRow: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        titleField.font = NSFont(name: "JetBrainsMonoNFM-Regular", size: 13)
            ?? NSFont.systemFont(ofSize: 13)
        subtitleField.font = NSFont.systemFont(ofSize: 10)
        subtitleField.textColor = .secondaryLabelColor
        addSubview(titleField)
        addSubview(subtitleField)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        titleField.frame = NSRect(x: 8, y: 12, width: bounds.width - 16, height: 16)
        subtitleField.frame = NSRect(x: 8, y: 0, width: bounds.width - 16, height: 12)
    }

    func configure(with cmd: Command, theme: Theme) {
        titleField.stringValue = "\(cmd.icon)  \(cmd.title)"
        subtitleField.stringValue = cmd.subtitle
    }
}

/// One command in the palette. Lightweight — just metadata + a closure.
struct Command {
    let icon: String      // Nerd Font glyph
    let title: String
    let subtitle: String  // shortcut hint or short description
    let run: (NSWindow?) -> Void

    static func all() -> [Command] {
        var out: [Command] = []

        // ChromeTheme switcher: one-shot apply that pairs a prompt preset
        // with the colour theme it was designed against. Users land here
        // first so the keyboard-only flow lets them sample the five built-
        // in identities before falling back to per-axis tuning.
        for chrome in ChromeTheme.all {
            out.append(Command(
                icon: "\u{f5fd}",  //   chevron-bar (chrome bundle)
                title: "Chrome: \(chrome.displayName)",
                subtitle: chrome.description,
                run: { _ in ConfigStore.shared.applyChromeTheme(chrome) }
            ))
        }

        // Per-theme switcher: leave granular axis controls below the bundle
        // entries for users who want a different colour with their current
        // prompt preset (or vice versa).
        for (i, name) in Theme.builtinNames.enumerated() {
            let key = i < 8 ? "⌘⌃\(i + 1)" : ""
            out.append(Command(
                icon: "\u{f53f}",  //   palette
                title: "Theme: \(name)",
                subtitle: key.isEmpty ? "Switch colour theme" : "Switch colour theme · \(key)",
                run: { _ in ConfigStore.shared.setTheme(named: name) }
            ))
        }

        // Pane / tab actions targeting the source window's responder chain.
        out.append(Command(
            icon: "\u{f0db}",  //  split vertical
            title: "Split Vertically",
            subtitle: "⌘D",
            run: { win in
                if let tw = win as? TerminalWindow { tw.splitPaneVertically(nil) }
            }
        ))
        out.append(Command(
            icon: "\u{f0c9}",  // ☰  split horizontal
            title: "Split Horizontally",
            subtitle: "⌘⇧D",
            run: { win in
                if let tw = win as? TerminalWindow { tw.splitPaneHorizontally(nil) }
            }
        ))
        out.append(Command(
            icon: "\u{f00d}",  // ✕  close
            title: "Close Pane",
            subtitle: "⌘W",
            run: { win in
                if let tw = win as? TerminalWindow { tw.closeActivePane(nil) }
            }
        ))
        out.append(Command(
            icon: "\u{f067}",  // +  new tab
            title: "New Tab",
            subtitle: "⌘T",
            run: { win in
                win?.newWindowForTab(nil)
            }
        ))

        // Prompt preset switcher: copies the bundled preset TOML over the
        // user's ~/.config/airterm/prompt.toml. airprompt re-reads its
        // config on every render, so the next prompt picks up the new style
        // automatically — no shell restart, no AirTerm reload.
        for preset in PromptPreset.all {
            out.append(Command(
                icon: "\u{f5fd}",  //   preset / chevron-bar
                title: "Prompt Preset: \(preset.name)",
                subtitle: preset.subtitle,
                run: { _ in PromptPreset.apply(preset) }
            ))
        }

        // Config: open the file in the user's editor. The file watcher in
        // ConfigStore picks up saves automatically — no explicit reload
        // command needed.
        out.append(Command(
            icon: "\u{f013}",  //   gear / config
            title: "Open Config",
            subtitle: "Open ~/.config/airterm/config.toml in default app",
            run: { _ in
                NSWorkspace.shared.open(Config.userConfigURL)
            }
        ))

        return out
    }
}

/// Static catalogue of prompt presets shipped under
/// `AirTerm.app/Contents/Resources/airprompt-presets/`. The command palette
/// surfaces these as "Prompt Preset: <name>" commands so users can switch
/// styles without ever leaving the keyboard.
struct PromptPreset {
    let name: String
    let subtitle: String

    static let all: [PromptPreset] = [
        PromptPreset(name: "pastel-powerline",
                     subtitle: "Bold colour blocks, Nerd Font icons"),
        PromptPreset(name: "tokyo-night",
                     subtitle: "Low-saturation purple/blue, bracketed segments"),
        PromptPreset(name: "gruvbox-rainbow",
                     subtitle: "Warm rainbow per module, includes clock"),
        PromptPreset(name: "jetpack",
                     subtitle: "Compact, 🚀 anchor, bold cyan path"),
        PromptPreset(name: "minimal",
                     subtitle: "Plain text, no icons, $ prompt"),
    ]

    /// Copies the bundled preset over `~/.config/airterm/prompt.toml`. Best-
    /// effort: failures are logged and surfaced via the status bar's next
    /// rebuild (the prompt simply stays on the previous style).
    static func apply(_ preset: PromptPreset) {
        let bundle = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/airprompt-presets")
            .appendingPathComponent("\(preset.name).toml")
        guard FileManager.default.fileExists(atPath: bundle.path) else {
            DebugLog.log("PromptPreset: bundled \(preset.name).toml not found")
            return
        }
        let dest = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/airterm/prompt.toml")
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Data.write(.atomic) handles both first-time create and overwrite,
        // and it never leaves a half-written file for airprompt to read
        // mid-switch.
        do {
            let data = try Data(contentsOf: bundle)
            try data.write(to: dest, options: .atomic)
            DebugLog.log("PromptPreset: applied \(preset.name)")
        } catch {
            DebugLog.log("PromptPreset: copy failed: \(error)")
        }
    }
}
