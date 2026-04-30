import AppKit

/// Callbacks the tab bar fires up to its owning window. The window mutates the
/// `Tab` array and re-installs the active pane container; the bar only knows
/// how to render and report clicks.
protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int)
    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int)
    func tabBarDidRequestNewTab(_ bar: TabBarView)
}

/// Self-rendered tab strip pinned to the top of `TerminalWindow`. Replaces the
/// macOS-native `tabbingMode = .preferred` chrome so we own the look (chips
/// shaped like Wezterm/iTerm2, theme-coloured, Nerd Font icons), and so each
/// tab can live inside the same NSWindow instead of as separate windows.
///
/// Layout: traffic lights occupy the leading 80pt region; chips fill the rest
/// up to a trailing "+" button. Chips share width evenly, clamped to a
/// reasonable `[chipMinWidth, chipMaxWidth]` band.
final class TabBarView: NSView {
    static let height: CGFloat = 32
    private static let leadingInset: CGFloat = 80   // traffic lights + buffer
    private static let trailingInset: CGFloat = 12
    private static let chipSpacing: CGFloat = 2
    private static let chipMinWidth: CGFloat = 100
    private static let chipMaxWidth: CGFloat = 240
    private static let newTabButtonWidth: CGFloat = 28

    weak var delegate: TabBarViewDelegate?

    /// Snapshot of tabs, by index. Owning window re-sets these on every tab
    /// mutation; `activeIndex` selects which chip renders highlighted.
    var tabs: [Tab] = [] { didSet { rebuild() } }
    var activeIndex: Int = 0 { didSet { rebuild() } }

    private var theme: Theme = ConfigStore.shared.theme
    private var configToken: UUID?
    private var chips: [TabChipView] = []
    private let newTabButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = backgroundCGColor()

        // Hairline bottom border to separate the tab strip from the pane area.
        let border = CALayer()
        border.frame = NSRect(x: 0, y: 0, width: frame.width, height: 1)
        border.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerMaxYMargin]
        layer?.addSublayer(border)

        configureNewTabButton()
        addSubview(newTabButton)

        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.theme = theme
            self?.layer?.backgroundColor = self?.backgroundCGColor()
            self?.rebuild()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

    deinit {
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
    }

    /// Plain NSView — let the window decide our height; never advertise a
    /// width that can shrink the window through `fittingSize`.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    private func configureNewTabButton() {
        newTabButton.bezelStyle = .regularSquare
        newTabButton.isBordered = false
        newTabButton.attributedTitle = Self.iconAttributedString(
            "\u{f067}",  //   plus
            size: 14,
            color: .secondaryLabelColor
        )
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.toolTip = "New Tab (⌘T)"
        newTabButton.focusRingType = .none
    }

    @objc private func newTabClicked() {
        delegate?.tabBarDidRequestNewTab(self)
    }

    /// Subtle tint slightly deeper than the terminal background so the strip
    /// reads as its own surface — same idea as the status bar but on top.
    private func backgroundCGColor() -> CGColor {
        let bg = theme.background
        let factor: Float = theme.isLight ? 0.94 : 0.85
        return CGColor(
            srgbRed: CGFloat(bg.x * factor),
            green: CGFloat(bg.y * factor),
            blue: CGFloat(bg.z * factor),
            alpha: 1
        )
    }

    /// Recreates chip subviews from `tabs`. Cheap (≤10 small NSViews) and
    /// only fires on tab tree mutations / focus changes / theme reloads.
    private func rebuild() {
        for chip in chips { chip.removeFromSuperview() }
        chips.removeAll(keepingCapacity: true)

        for (i, tab) in tabs.enumerated() {
            let chip = TabChipView()
            let active = (i == activeIndex)
            chip.configure(tab: tab, isActive: active, theme: theme)
            chip.onClick = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didSelectTabAt: i)
            }
            chip.onClose = { [weak self] in
                guard let self else { return }
                self.delegate?.tabBar(self, didCloseTabAt: i)
            }
            addSubview(chip, positioned: .below, relativeTo: newTabButton)
            chips.append(chip)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let chipAreaWidth = bounds.width
            - Self.leadingInset
            - Self.trailingInset
            - Self.newTabButtonWidth
        let count = max(1, chips.count)
        let raw = (chipAreaWidth - CGFloat(count - 1) * Self.chipSpacing) / CGFloat(count)
        let chipWidth = max(Self.chipMinWidth, min(Self.chipMaxWidth, raw))

        let chipHeight = Self.height - 6
        let yChip = (Self.height - chipHeight) / 2

        var x = Self.leadingInset
        for chip in chips {
            chip.frame = NSRect(x: x, y: yChip, width: chipWidth, height: chipHeight)
            x += chipWidth + Self.chipSpacing
        }

        // "+" button trails the last chip, capped to the right edge so it
        // doesn't escape the bar when many tabs are open.
        let buttonX = min(x + 4, bounds.width - Self.trailingInset - Self.newTabButtonWidth)
        newTabButton.frame = NSRect(
            x: buttonX,
            y: yChip,
            width: Self.newTabButtonWidth,
            height: chipHeight
        )
    }

    /// Shared helper: NF glyph rendered as the button/chip's title with a
    /// foreground colour we control (NSAttributedString side-steps NSButton's
    /// default tint mode).
    static func iconAttributedString(_ glyph: String, size: CGFloat, color: NSColor) -> NSAttributedString {
        let font = NSFont(name: "JetBrainsMonoNFM-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size)
        return NSAttributedString(string: glyph, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }
}

/// One tab "chip". Rounded rectangle + icon + title + close button. The chip
/// itself swallows clicks (returning `self` from `hitTest`) so users don't
/// accidentally tap the title label and miss the selection callback. The
/// close button is the only child that hit-tests through.
final class TabChipView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    private var isActive = false
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6

        iconLabel.font = NSFont(name: "JetBrainsMonoNFM-Regular", size: 13)
            ?? NSFont.systemFont(ofSize: 13)
        iconLabel.alignment = .center
        iconLabel.isBordered = false
        iconLabel.isBezeled = false
        iconLabel.drawsBackground = false
        iconLabel.isEditable = false
        iconLabel.isSelectable = false
        addSubview(iconLabel)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.attributedTitle = TabBarView.iconAttributedString(
            "\u{f00d}",  // ✕  fa-times
            size: 9,
            color: .secondaryLabelColor
        )
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.focusRingType = .none
        addSubview(closeButton)

        let track = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(track)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: Tab, isActive: Bool, theme: Theme) {
        self.isActive = isActive
        iconLabel.stringValue = tab.icon
        titleLabel.stringValue = tab.title
        applyStyle(theme: theme)
        // Keep the close button visible whenever the chip is active so the
        // user always has a 1-click way out of the current tab.
        closeButton.isHidden = !(isActive || isHovered)
    }

    private func applyStyle(theme: Theme) {
        let fg = theme.foreground
        let accent = theme.accent
        if isActive {
            // Active: slightly lighter than the bar, accent-coloured icon.
            let bg = theme.background
            layer?.backgroundColor = CGColor(
                srgbRed: CGFloat(bg.x), green: CGFloat(bg.y),
                blue: CGFloat(bg.z), alpha: 1
            )
            iconLabel.textColor = NSColor(
                srgbRed: CGFloat(accent.x), green: CGFloat(accent.y),
                blue: CGFloat(accent.z), alpha: 1
            )
            titleLabel.textColor = NSColor(
                srgbRed: CGFloat(fg.x), green: CGFloat(fg.y),
                blue: CGFloat(fg.z), alpha: 1
            )
        } else {
            // Inactive: low-contrast tint, dim text.
            layer?.backgroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.04)
            iconLabel.textColor = .secondaryLabelColor
            titleLabel.textColor = NSColor(
                srgbRed: CGFloat(fg.x), green: CGFloat(fg.y),
                blue: CGFloat(fg.z), alpha: 0.7
            )
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconLabel.frame = NSRect(x: 8, y: 0, width: 18, height: h)
        let titleX: CGFloat = 30
        let closeArea: CGFloat = 22
        let titleW = max(0, bounds.width - titleX - closeArea)
        titleLabel.frame = NSRect(x: titleX, y: 0, width: titleW, height: h)
        closeButton.frame = NSRect(x: bounds.width - 20, y: (h - 14) / 2, width: 14, height: 14)
    }

    /// Funnel all mouse events to self unless they land on the close button —
    /// otherwise the title's NSTextField swallows clicks even though it's
    /// non-editable, and the chip never gets a `mouseDown`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if !closeButton.isHidden, closeButton.frame.contains(local) {
            return closeButton.hitTest(point)
        }
        return self
    }

    @objc private func closeClicked() {
        onClose?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        closeButton.isHidden = !isActive
    }
}
