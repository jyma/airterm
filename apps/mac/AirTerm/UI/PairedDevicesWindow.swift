import AppKit

/// Phones the user has previously paired with this Mac, surfaced as a
/// table so they can see what's on the books and revoke any of them.
///
/// The Mac side has tracked `PairedPhone` records since P3-3d, but
/// until now there was no UI to inspect or remove them — users
/// unpairing a phone had to drop UserDefaults manually. This panel
/// closes that gap.
///
/// Wired via:
///   • File → Paired Devices… (also reachable from ⇧⌘P)
///   • Forget tears down any live TakeoverSession + clears the
///     PairingStore record + tells the PairingCoordinator to drop
///     trust for that device id.
final class PairedDevicesWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    /// Closure the panel calls when the user taps "Forget". The owner
    /// (AppDelegate) coordinates teardown across TakeoverSession +
    /// PairingCoordinator so live mirrors stop cleanly.
    var onForget: ((String) -> Void)?

    /// Closure that returns the set of currently-active phone device
    /// ids — drives the green "Live" pill on rows that are mirroring
    /// right now. Refreshed on every window open / reload.
    var activePhoneIdsProvider: (() -> Set<String>)?

    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var phones: [PairedPhone] = []
    private var activeIds: Set<String> = []
    private var configToken: UUID?
    private var theme: Theme = ConfigStore.shared.theme

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Paired Devices"
        isFloatingPanel = false
        level = .normal
        setupContent()
        applyTheme(ConfigStore.shared.theme)

        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.theme = theme
            self?.applyTheme(theme)
            self?.table.reloadData()
        }
    }

    deinit {
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
    }

    /// Refresh data + re-render. Called by the panel itself on open and
    /// from outside whenever a takeover session ends so the "Live"
    /// pills flip to grey without the user reopening.
    func reload() {
        phones = PairingStore.loadPairedPhones()
        activeIds = activePhoneIdsProvider?() ?? []
        table.reloadData()
        emptyLabel.isHidden = !phones.isEmpty
        scroll.isHidden = phones.isEmpty
    }

    // MARK: - Layout

    private func setupContent() {
        guard let content = contentView else { return }
        content.wantsLayer = true

        scroll.frame = content.bounds.insetBy(dx: 16, dy: 16)
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .lineBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        table.headerView = nil
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.rowHeight = 56
        table.allowsMultipleSelection = false
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("phone"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)

        scroll.documentView = table
        content.addSubview(scroll)

        emptyLabel.frame = content.bounds
        emptyLabel.autoresizingMask = [.width, .height]
        emptyLabel.alignment = .center
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.stringValue = "No paired devices yet.\nUse File → Pair New Device… to add one."
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.isHidden = true
        content.addSubview(emptyLabel)
    }

    private func applyTheme(_ theme: Theme) {
        guard let content = contentView else { return }
        let bg = theme.background
        content.layer?.backgroundColor = CGColor(
            srgbRed: CGFloat(bg.x), green: CGFloat(bg.y),
            blue: CGFloat(bg.z), alpha: 1
        )
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { phones.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let phone = phones[row]
        let isActive = activeIds.contains(phone.deviceId)
        let id = NSUserInterfaceItemIdentifier("paired-phone-row")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PairedPhoneRowView)
            ?? PairedPhoneRowView()
        cell.identifier = id
        cell.configure(
            phone: phone,
            isActive: isActive,
            theme: theme,
            onForget: { [weak self] in
                guard let self else { return }
                self.onForget?(phone.deviceId)
                self.reload()
            }
        )
        return cell
    }
}

// MARK: - Row view

private final class PairedPhoneRowView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let livePill = NSTextField(labelWithString: "")
    private let forgetButton = NSButton(title: "Forget", target: nil, action: nil)
    private var onForget: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(detailLabel)

        livePill.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        livePill.alignment = .center
        livePill.wantsLayer = true
        livePill.layer?.cornerRadius = 9
        livePill.isBordered = false
        livePill.drawsBackground = false
        livePill.isHidden = true
        addSubview(livePill)

        forgetButton.bezelStyle = .rounded
        forgetButton.target = self
        forgetButton.action = #selector(forgetClicked)
        forgetButton.controlSize = .small
        addSubview(forgetButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func forgetClicked() {
        // Confirm in-place — irreversible action. The next call goes
        // straight to the persistence + session-teardown path so the
        // alert IS the only safety net.
        let alert = NSAlert()
        alert.messageText = "Forget this phone?"
        alert.informativeText = "Future connection attempts from \(nameLabel.stringValue) will be rejected. The phone keeps its end of the pairing until it scans a new QR."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onForget?()
        }
    }

    func configure(phone: PairedPhone, isActive: Bool, theme: Theme, onForget: @escaping () -> Void) {
        self.onForget = onForget
        nameLabel.stringValue = phone.name
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: phone.pairedAt)
        let shortId = phone.deviceId.count > 12
            ? String(phone.deviceId.prefix(8)) + "…"
            : phone.deviceId
        detailLabel.stringValue = "Paired \(when) · \(shortId)"
        if isActive {
            livePill.stringValue = "LIVE"
            let g = theme.successColor
            livePill.layer?.backgroundColor = CGColor(
                srgbRed: CGFloat(g.x), green: CGFloat(g.y),
                blue: CGFloat(g.z), alpha: 0.18
            )
            livePill.textColor = NSColor(
                srgbRed: CGFloat(g.x), green: CGFloat(g.y),
                blue: CGFloat(g.z), alpha: 1
            )
            livePill.isHidden = false
        } else {
            livePill.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let buttonW: CGFloat = 80
        let buttonH: CGFloat = 24
        let pillW: CGFloat = 44
        let pillH: CGFloat = 18

        forgetButton.frame = NSRect(
            x: bounds.width - pad - buttonW,
            y: (bounds.height - buttonH) / 2,
            width: buttonW,
            height: buttonH
        )

        // "LIVE" pill sits between text and the Forget button when shown.
        livePill.frame = NSRect(
            x: forgetButton.frame.minX - pillW - 8,
            y: (bounds.height - pillH) / 2,
            width: pillW,
            height: pillH
        )

        let textRight = (livePill.isHidden ? forgetButton.frame.minX : livePill.frame.minX) - 8
        let textW = max(80, textRight - pad)
        nameLabel.frame = NSRect(x: pad, y: bounds.height / 2 + 1, width: textW, height: 18)
        detailLabel.frame = NSRect(x: pad, y: bounds.height / 2 - 18, width: textW, height: 14)
    }
}
