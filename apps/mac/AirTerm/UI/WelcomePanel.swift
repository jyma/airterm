import AppKit

/// Transient first-launch panel that surfaces the keyboard shortcuts a
/// new user can't discover from the visible chrome alone — the command
/// palette, split-pane bindings, tab keys, and the Pair entry point.
///
/// Lifecycle: AppDelegate creates one on `applicationDidFinishLaunching`
/// when the `airterm.welcomeShown` UserDefaults flag is unset. The panel
/// auto-dismisses after `autoDismissAfter` seconds or on click anywhere
/// inside it; either path persists the flag so subsequent launches stay
/// quiet.
///
/// Visual: small floating panel anchored to the lower-right of the main
/// window, theme-tinted background, monospace key chips on the left of
/// each row. No close button — the auto-dismiss is the affordance, and
/// the "Don't show again" cue is implicit (the panel really doesn't
/// come back).
final class WelcomePanel: NSPanel {
    private static let autoDismissAfter: TimeInterval = 12
    private static let userDefaultsKey = "airterm.welcomeShown"

    private var configToken: UUID?
    private var dismissTimer: Timer?

    /// Returns true if this Mac install hasn't seen the welcome panel
    /// yet. AppDelegate uses this to gate panel construction so we
    /// don't allocate AppKit objects we'll never show.
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Marks the welcome as shown so the next launch skips it. Called
    /// from the dismiss path; also exposed publicly for tests / explicit
    /// "skip onboarding" reset paths.
    static func markShown() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.applyTheme(theme)
        }
        setupContent()
        applyTheme(ConfigStore.shared.theme)
    }

    deinit {
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
        dismissTimer?.invalidate()
    }

    /// Show + auto-dismiss schedule. Anchors near the lower-right corner
    /// of `relativeTo` so the panel never covers the active prompt area.
    func present(over relativeTo: NSWindow?) {
        if let host = relativeTo {
            let f = host.frame
            let panel = frame
            // 24pt inset from right + bottom of the host so the panel
            // visibly belongs to the window rather than the screen.
            let x = f.maxX - panel.width - 24
            let y = f.minY + 24
            setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        scheduleDismiss()
    }

    // MARK: - Layout

    private let titleField = NSTextField(labelWithString: "Welcome to AirTerm")
    private let subtitleField = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private let footerHint = NSTextField(labelWithString: "Tap anywhere to dismiss")

    private func setupContent() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true

        titleField.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.frame = NSRect(x: 18, y: 200, width: 304, height: 22)
        titleField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(titleField)

        subtitleField.stringValue = "Quick keys to know:"
        subtitleField.font = NSFont.systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.frame = NSRect(x: 18, y: 178, width: 304, height: 18)
        subtitleField.autoresizingMask = [.width, .minYMargin]
        content.addSubview(subtitleField)

        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.frame = NSRect(x: 18, y: 36, width: 304, height: 132)
        stack.autoresizingMask = [.width, .height]

        let rows: [(String, String)] = [
            ("⇧⌘P",       "Command Palette"),
            ("⌘D / ⌘⇧D",  "Split pane V / H"),
            ("⌘T",        "New tab"),
            ("File → Pair", "Mirror to phone"),
            ("⌃⌘1…8",     "Switch theme"),
        ]
        for (key, label) in rows {
            stack.addArrangedSubview(makeRow(keyText: key, label: label))
        }
        content.addSubview(stack)

        footerHint.font = NSFont.systemFont(ofSize: 11)
        footerHint.textColor = .tertiaryLabelColor
        footerHint.alignment = .center
        footerHint.frame = NSRect(x: 18, y: 12, width: 304, height: 16)
        footerHint.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(footerHint)

        // Whole-panel click-to-dismiss via a tracking view that fills
        // the surface and sits on top of every label.
        let dismissView = ClickThroughView { [weak self] in self?.dismiss() }
        dismissView.frame = content.bounds
        dismissView.autoresizingMask = [.width, .height]
        content.addSubview(dismissView)
    }

    private func makeRow(keyText: String, label: String) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 22))

        let chip = NSTextField(labelWithString: keyText)
        chip.font = NSFont(name: "JetBrainsMonoNFM-Regular", size: 11)
            ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        chip.alignment = .center
        chip.textColor = .labelColor
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 4
        chip.frame = NSRect(x: 0, y: 2, width: 110, height: 18)
        row.addSubview(chip)

        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 12)
        labelField.textColor = .labelColor
        labelField.frame = NSRect(x: 122, y: 2, width: 180, height: 18)
        row.addSubview(labelField)

        // Carry chip ref on row layer-name so applyTheme can re-tint
        // without searching by index.
        chip.identifier = NSUserInterfaceItemIdentifier("welcome-chip")
        return row
    }

    private func applyTheme(_ theme: Theme) {
        guard let content = contentView else { return }
        let bg = theme.background
        // 88% opacity so the prompt under the panel still hints at
        // its presence — feels less modal than an opaque sheet.
        content.layer?.backgroundColor = CGColor(
            srgbRed: CGFloat(bg.x), green: CGFloat(bg.y),
            blue: CGFloat(bg.z), alpha: 0.88
        )
        // Re-tint key chips with the theme's tertiary surface so they
        // sit on the panel without competing with the description text.
        for view in stack.arrangedSubviews {
            for sub in view.subviews {
                guard let label = sub as? NSTextField,
                      label.identifier?.rawValue == "welcome-chip" else { continue }
                label.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
                label.textColor = NSColor(
                    srgbRed: CGFloat(theme.accent.x),
                    green: CGFloat(theme.accent.y),
                    blue: CGFloat(theme.accent.z),
                    alpha: 1
                )
            }
        }
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: Self.autoDismissAfter,
            repeats: false
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    fileprivate func dismiss() {
        Self.markShown()
        dismissTimer?.invalidate()
        dismissTimer = nil
        orderOut(nil)
    }
}

// MARK: - ClickThroughView

/// Transparent overlay that swallows mouse clicks so anywhere on the
/// panel becomes a "dismiss" affordance, while still letting AppKit
/// route hover / focus events to the labels behind it.
private final class ClickThroughView: NSView {
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
