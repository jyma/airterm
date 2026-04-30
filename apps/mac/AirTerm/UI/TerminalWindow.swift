import AppKit

enum FocusDirection { case left, right, up, down }

final class TerminalWindow: NSWindow {
    private var rootPane: Pane!
    private var container: PaneContainerView!
    private var statusBar: StatusBarView!

    private weak var activeTerminalView: TerminalView? {
        didSet {
            oldValue?.isActive = false
            activeTerminalView?.isActive = true
        }
    }

    /// Flip every leaf's `hasSiblings` flag after a pane-tree mutation so the
    /// focus border only renders when there's more than one pane. Also keeps
    /// the status bar's pane-count badge in sync.
    private func syncPaneSiblings() {
        let leaves = rootPane.leaves
        let multiple = leaves.count > 1
        for leaf in leaves {
            leaf.terminalView?.hasSiblings = multiple
        }
        statusBar?.paneCount = leaves.count
    }

    private var configToken: UUID?

    private func applyTheme(_ theme: Theme) {
        let bg = theme.background
        backgroundColor = NSColor(
            srgbRed: CGFloat(bg.x),
            green: CGFloat(bg.y),
            blue: CGFloat(bg.z),
            alpha: 1
        )
    }

    deinit {
        if let token = configToken {
            ConfigStore.shared.unsubscribe(token)
        }
    }

    /// Reserved height (in points) at the top of the content area so the
    /// traffic-light buttons and (when present) the system tab bar don't
    /// overlap the terminal grid. 28pt matches macOS's stock title-bar height.
    static let titleBarInset: CGFloat = 28

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            // .fullSizeContentView lets us paint the theme background under the
            // titlebar so traffic-lights look "floating" Ghostty-style, while a
            // 28pt top inset keeps the terminal grid clear of them.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "AirTerm"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        minSize = NSSize(width: 480, height: 320)
        tabbingMode = .preferred
        tabbingIdentifier = "airterm.tab-group"
        // ARC manages window lifetime; AppKit's legacy auto-release on close
        // otherwise double-releases the window (crashes on tab close).
        isReleasedWhenClosed = false

        applyTheme(ConfigStore.shared.theme)
        alphaValue = CGFloat(ConfigStore.shared.config.window.opacity)

        configToken = ConfigStore.shared.subscribe { [weak self] config, theme in
            self?.applyTheme(theme)
            self?.alphaValue = CGFloat(config.window.opacity)
        }

        guard let content = contentView else { return }

        let firstTV = makeTerminalView(frame: .zero)
        let firstLeaf = Pane.leaf(firstTV)
        self.rootPane = firstLeaf
        self.activeTerminalView = firstTV

        // macOS y-up coords: y=0 is bottom of contentView. Status bar pinned
        // to the bottom, pane container fills the middle, traffic lights
        // float in the top-28pt strip we leave clear.
        // We use autoresizingMask (not auto-layout) so subview intrinsic
        // sizes never bubble up to NSWindow's fittingSize and collapse the
        // frame to ~110pt the way auto-laid-out NSStackView children do.
        let cw = content.bounds.width
        let ch = content.bounds.height
        let statusH = StatusBarView.height
        let titleH = Self.titleBarInset

        let statusBar = StatusBarView(
            frame: NSRect(x: 0, y: 0, width: cw, height: statusH)
        )
        statusBar.autoresizingMask = [.width]
        content.addSubview(statusBar)
        self.statusBar = statusBar

        let container = PaneContainerView(
            frame: NSRect(x: 0, y: statusH, width: cw, height: ch - statusH - titleH),
            root: firstLeaf
        )
        container.autoresizingMask = [.width, .height]
        content.addSubview(container)
        self.container = container

        syncPaneSiblings()

        // Block macOS state restoration (which silently clamps our frame to
        // a previous session's smaller size) and force the initial frame.
        isRestorable = false
        setFrameAutosaveName("")
        setFrame(
            NSRect(x: 100, y: 100, width: 1200, height: 800),
            display: false
        )

        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(firstTV)
        }
    }

    private func makeTerminalView(frame: NSRect) -> TerminalView {
        let tv = TerminalView(frame: frame)
        tv.autoresizingMask = [.width, .height]
        tv.onActivated = { [weak self, weak tv] in
            guard let tv else { return }
            self?.activeTerminalView = tv
        }
        return tv
    }

    // MARK: - Menu actions (responder-chain dispatched)

    @objc func splitPaneVertically(_ sender: Any?) { split(.vertical) }
    @objc func splitPaneHorizontally(_ sender: Any?) { split(.horizontal) }

    @objc func closeActivePane(_ sender: Any?) {
        guard let tv = activeTerminalView else { close(); return }
        closePane(containing: tv)
    }

    @objc func focusNextPane(_ sender: Any?) { cycleFocus(forward: true) }
    @objc func focusPreviousPane(_ sender: Any?) { cycleFocus(forward: false) }

    // MARK: - Tabs

    override func newWindowForTab(_ sender: Any?) {
        let new = TerminalWindow()
        addTabbedWindow(new, ordered: .above)
        new.makeKeyAndOrderFront(nil)
    }

    @objc func selectTabByTag(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let group = tabGroup,
              item.tag >= 0,
              item.tag < group.windows.count
        else { return }
        group.windows[item.tag].makeKeyAndOrderFront(nil)
    }
    @objc func focusPaneLeft(_ sender: Any?) { moveFocus(.left) }
    @objc func focusPaneRight(_ sender: Any?) { moveFocus(.right) }
    @objc func focusPaneUp(_ sender: Any?) { moveFocus(.up) }
    @objc func focusPaneDown(_ sender: Any?) { moveFocus(.down) }

    // MARK: - Focus navigation

    private func cycleFocus(forward: Bool) {
        let leaves = rootPane.leaves
        guard leaves.count > 1,
              let active = activeTerminalView,
              let idx = leaves.firstIndex(where: { $0.terminalView === active })
        else { return }
        let next = forward
            ? (idx + 1) % leaves.count
            : (idx + leaves.count - 1) % leaves.count
        if let tv = leaves[next].terminalView {
            makeFirstResponder(tv)
        }
    }

    private func moveFocus(_ direction: FocusDirection) {
        guard let active = activeTerminalView else { return }
        let activeFrame = active.convert(active.bounds, to: nil)
        let candidates = rootPane.leaves.compactMap(\.terminalView).filter { $0 !== active }

        var best: TerminalView?
        var bestDistance = CGFloat.infinity
        for tv in candidates {
            let frame = tv.convert(tv.bounds, to: nil)
            guard let d = Self.directionalDistance(from: activeFrame, to: frame, direction: direction) else { continue }
            if d < bestDistance {
                bestDistance = d
                best = tv
            }
        }
        if let best { makeFirstResponder(best) }
    }

    private static func directionalDistance(from src: NSRect, to dst: NSRect, direction: FocusDirection) -> CGFloat? {
        // Window coords are y-up: maxY = top edge, minY = bottom edge.
        switch direction {
        case .left:
            guard dst.maxX <= src.minX else { return nil }
            return (src.minX - dst.maxX) + abs(src.midY - dst.midY) * 0.5
        case .right:
            guard dst.minX >= src.maxX else { return nil }
            return (dst.minX - src.maxX) + abs(src.midY - dst.midY) * 0.5
        case .up:
            guard dst.minY >= src.maxY else { return nil }
            return (dst.minY - src.maxY) + abs(src.midX - dst.midX) * 0.5
        case .down:
            guard dst.maxY <= src.minY else { return nil }
            return (src.minY - dst.maxY) + abs(src.midX - dst.midX) * 0.5
        }
    }

    private func split(_ orientation: SplitOrientation) {
        guard let active = activeTerminalView,
              let activeLeaf = rootPane.leaves.first(where: { $0.terminalView === active })
        else { return }

        let newTV = makeTerminalView(frame: .zero)
        let newLeaf = Pane.leaf(newTV)

        if let parent = activeLeaf.parent, parent.orientation == orientation {
            let idx = parent.children.firstIndex { $0 === activeLeaf } ?? parent.children.count - 1
            parent.children.insert(newLeaf, at: idx + 1)
            newLeaf.parent = parent
        } else {
            let oldParent = activeLeaf.parent
            let newSplit = Pane.split(orientation, children: [activeLeaf, newLeaf])
            newSplit.parent = oldParent
            if let oldParent {
                let idx = oldParent.children.firstIndex { $0 === activeLeaf } ?? 0
                oldParent.children[idx] = newSplit
            } else {
                rootPane = newSplit
            }
        }

        container.setRoot(rootPane)
        syncPaneSiblings()
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(newTV)
        }
    }

    private func closePane(containing tv: TerminalView) {
        guard let leaf = rootPane.leaves.first(where: { $0.terminalView === tv }) else { return }

        tv.session.stop()

        guard let parent = leaf.parent else {
            // Last pane -> close the window.
            close()
            return
        }

        parent.children.removeAll { $0 === leaf }

        if parent.children.count == 1 {
            let only = parent.children[0]
            if let grandparent = parent.parent {
                let idx = grandparent.children.firstIndex { $0 === parent } ?? 0
                grandparent.children[idx] = only
                only.parent = grandparent
            } else {
                rootPane = only
                only.parent = nil
            }
        }

        container.setRoot(rootPane)
        syncPaneSiblings()

        if let firstLeaf = rootPane.leaves.first, let newFocus = firstLeaf.terminalView {
            activeTerminalView = newFocus
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(newFocus)
            }
        }
    }
}

