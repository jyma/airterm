import AppKit

enum FocusDirection { case left, right, up, down }

/// Single NSWindow that hosts an arbitrary number of `Tab`s. We disable
/// macOS's native tabbing (`tabbingMode = .disallowed`) and render our own
/// tab strip via `TabBarView`, mirroring iTerm2 / Wezterm / Ghostty's modern
/// "one window, many tabs" model. Each tab owns an independent pane tree;
/// switching tabs reparents the existing container — sessions and Metal
/// renderers keep running across switches.
final class TerminalWindow: NSWindow, TabBarViewDelegate {
    private var tabs: [Tab] = []
    private var activeTabIndex: Int = 0
    private var activeTab: Tab? {
        tabs.indices.contains(activeTabIndex) ? tabs[activeTabIndex] : nil
    }

    private var tabBar: TabBarView!
    private var statusBar: StatusBarView!
    private var paneHost: NSView!

    private weak var activeTerminalView: TerminalView? {
        didSet {
            oldValue?.isActive = false
            // Stop pushing cwd updates from a pane that's no longer focused
            // so the status bar reflects exactly the active session's cwd.
            oldValue?.session.onCwdChange = nil
            activeTerminalView?.isActive = true
            // Mirror onto the active tab so subsequent tab switches restore
            // focus to the same pane the user last interacted with.
            if let tv = activeTerminalView, let tab = activeTab {
                tab.activeTerminalView = tv
            }
            wireActiveSession()
        }
    }

    /// Attach the active session's OSC 7 cwd stream to the status bar AND
    /// the tab bar so both surfaces refresh whenever the user `cd`s.
    private func wireActiveSession() {
        guard let tv = activeTerminalView else { return }
        tv.session.onCwdChange = { [weak self] path in
            DispatchQueue.main.async {
                self?.statusBar?.updateCwd(path)
                self?.refreshTabBarTitles()
            }
        }
        statusBar?.updateCwd(tv.session.cwd)
        refreshTabBarTitles()
    }

    /// Flip every leaf's `hasSiblings` flag after a pane-tree mutation in the
    /// active tab so the focus dim only kicks in when there's more than one
    /// pane. Also keeps the status bar's pane-count badge in sync.
    private func syncPaneSiblings() {
        guard let tab = activeTab else { return }
        let leaves = tab.rootPane.leaves
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
    /// traffic-light buttons don't overlap the terminal grid. The custom
    /// tab bar fills exactly this region — its leading inset (`80pt`) keeps
    /// chip rendering clear of the traffic-light cluster.
    static let titleBarInset: CGFloat = TabBarView.height

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            // .fullSizeContentView lets us paint the theme background under
            // the titlebar so traffic-lights look "floating" Ghostty-style;
            // the custom tab bar covers the same vertical strip.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "AirTerm"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        minSize = NSSize(width: 480, height: 320)
        // We render our own tab strip; opt out of the macOS-native one so it
        // doesn't double-up underneath ours.
        tabbingMode = .disallowed
        // ARC manages window lifetime; AppKit's legacy auto-release on close
        // otherwise double-releases the window.
        isReleasedWhenClosed = false

        applyTheme(ConfigStore.shared.theme)
        alphaValue = CGFloat(ConfigStore.shared.config.window.opacity)

        configToken = ConfigStore.shared.subscribe { [weak self] config, theme in
            self?.applyTheme(theme)
            self?.alphaValue = CGFloat(config.window.opacity)
        }

        guard let content = contentView else { return }

        // macOS y-up: status bar pinned to bottom, tab bar to top, pane host
        // fills the middle strip. Autoresizing masks (not auto-layout) so
        // subview intrinsic sizes never bubble up to NSWindow.fittingSize.
        let cw = content.bounds.width
        let ch = content.bounds.height
        let statusH = StatusBarView.height
        let tabH = TabBarView.height
        let hostH = ch - statusH - tabH

        let statusBar = StatusBarView(
            frame: NSRect(x: 0, y: 0, width: cw, height: statusH)
        )
        statusBar.autoresizingMask = [.width]
        content.addSubview(statusBar)
        self.statusBar = statusBar

        let host = NSView(frame: NSRect(x: 0, y: statusH, width: cw, height: hostH))
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        content.addSubview(host)
        self.paneHost = host

        let tabBar = TabBarView(
            frame: NSRect(x: 0, y: ch - tabH, width: cw, height: tabH)
        )
        tabBar.autoresizingMask = [.width, .minYMargin]
        tabBar.delegate = self
        content.addSubview(tabBar)
        self.tabBar = tabBar

        // First tab.
        let firstTab = makeNewTab(initialFrame: host.bounds)
        tabs.append(firstTab)
        installActiveTab()

        // Block macOS state restoration (which silently clamps our frame to
        // a previous session's smaller size) and force the initial frame.
        isRestorable = false
        setFrameAutosaveName("")
        setFrame(
            NSRect(x: 100, y: 100, width: 1200, height: 800),
            display: false
        )
    }

    // MARK: - Tab construction

    /// Build a fresh terminal view + leaf + pane container, packaged as a Tab.
    /// Caller decides whether to install it (via `installActiveTab()`) or just
    /// keep it parked.
    private func makeNewTab(initialFrame: NSRect) -> Tab {
        let tv = makeTerminalView(frame: .zero)
        let leaf = Pane.leaf(tv)
        let container = PaneContainerView(frame: initialFrame, root: leaf)
        container.autoresizingMask = [.width, .height]
        return Tab(rootPane: leaf, container: container)
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

    /// Reparents the active tab's pane container into `paneHost`, syncs the
    /// tab bar / status bar / focus pane, and makes the tab's saved active
    /// terminal view first responder. Idempotent — safe to call after every
    /// tab tree mutation.
    private func installActiveTab() {
        guard let tab = activeTab else { return }

        // Detach any other tab's container first so only one renders.
        for (i, other) in tabs.enumerated() where i != activeTabIndex {
            if other.paneContainer.superview === paneHost {
                other.paneContainer.removeFromSuperview()
            }
        }

        // Attach this tab's container if it isn't already mounted.
        if tab.paneContainer.superview !== paneHost {
            tab.paneContainer.frame = paneHost.bounds
            paneHost.addSubview(tab.paneContainer)
        }

        // Sync chrome.
        tabBar.tabs = tabs
        tabBar.activeIndex = activeTabIndex
        syncPaneSiblings()

        // Refocus the saved active pane in this tab.
        let target = tab.activeTerminalView ?? tab.rootPane.leaves.first?.terminalView
        if let target {
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(target)
            }
            self.activeTerminalView = target
        }
    }

    /// Cheap update path when only titles / icons change (cwd shifts inside a
    /// tab). Avoids the chip-recreate cost of `rebuild()`.
    private func refreshTabBarTitles() {
        // The TabBarView rebuilds chips when `tabs` is reassigned. Reassign
        // to the same array literal to trigger didSet — chip count and
        // identity are unchanged so this is effectively a re-render only.
        tabBar.tabs = tabs
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

    // MARK: - Tabs (custom — replaces the macOS-native tabbingMode workflow)

    /// ⌘T – append a new tab and select it.
    @objc func newTab(_ sender: Any?) {
        addTab()
    }

    /// Compatibility: the File menu's "New Tab" item still uses the
    /// `newWindowForTab(_:)` selector for muscle memory; route it to our
    /// in-window tab path.
    override func newWindowForTab(_ sender: Any?) {
        addTab()
    }

    private func addTab() {
        let new = makeNewTab(initialFrame: paneHost.bounds)
        tabs.append(new)
        activeTabIndex = tabs.count - 1
        installActiveTab()
    }

    @objc func selectTabByTag(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              item.tag >= 0,
              item.tag < tabs.count
        else { return }
        selectTab(at: item.tag)
    }

    override func selectNextTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }

    override func selectPreviousTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex + tabs.count - 1) % tabs.count)
    }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index), index != activeTabIndex else { return }
        activeTabIndex = index
        installActiveTab()
    }

    /// Fully tears down a tab — stops every PTY in its tree, drops the
    /// container, removes the tab from the array, and either selects a
    /// neighbour or closes the window if it was the last tab.
    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        for tv in tab.allTerminalViews {
            tv.session.stop()
        }
        if tab.paneContainer.superview === paneHost {
            tab.paneContainer.removeFromSuperview()
        }
        tabs.remove(at: index)

        if tabs.isEmpty {
            close()
            return
        }
        activeTabIndex = max(0, min(tabs.count - 1, index <= activeTabIndex ? activeTabIndex - 1 : activeTabIndex))
        if activeTabIndex < 0 { activeTabIndex = 0 }
        installActiveTab()
    }

    // MARK: - TabBarViewDelegate

    func tabBar(_ bar: TabBarView, didSelectTabAt index: Int) {
        selectTab(at: index)
    }

    func tabBar(_ bar: TabBarView, didCloseTabAt index: Int) {
        closeTab(at: index)
    }

    func tabBarDidRequestNewTab(_ bar: TabBarView) {
        addTab()
    }

    @objc func focusPaneLeft(_ sender: Any?) { moveFocus(.left) }
    @objc func focusPaneRight(_ sender: Any?) { moveFocus(.right) }
    @objc func focusPaneUp(_ sender: Any?) { moveFocus(.up) }
    @objc func focusPaneDown(_ sender: Any?) { moveFocus(.down) }

    // MARK: - Focus navigation

    private func cycleFocus(forward: Bool) {
        guard let tab = activeTab else { return }
        let leaves = tab.rootPane.leaves
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
        guard let tab = activeTab, let active = activeTerminalView else { return }
        let activeFrame = active.convert(active.bounds, to: nil)
        let candidates = tab.rootPane.leaves.compactMap(\.terminalView).filter { $0 !== active }

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
        guard let tab = activeTab,
              let active = activeTerminalView,
              let activeLeaf = tab.rootPane.leaves.first(where: { $0.terminalView === active })
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
                tab.rootPane = newSplit
            }
        }

        tab.paneContainer.setRoot(tab.rootPane)
        syncPaneSiblings()
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(newTV)
        }
    }

    private func closePane(containing tv: TerminalView) {
        guard let tab = activeTab,
              let leaf = tab.rootPane.leaves.first(where: { $0.terminalView === tv })
        else { return }

        tv.session.stop()

        guard let parent = leaf.parent else {
            // Last pane in this tab → close the tab. closeTab handles the
            // last-tab-in-window case by closing the window itself.
            closeTab(at: activeTabIndex)
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
                tab.rootPane = only
                only.parent = nil
            }
        }

        tab.paneContainer.setRoot(tab.rootPane)
        syncPaneSiblings()

        if let firstLeaf = tab.rootPane.leaves.first, let newFocus = firstLeaf.terminalView {
            activeTerminalView = newFocus
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(newFocus)
            }
        }
    }
}
