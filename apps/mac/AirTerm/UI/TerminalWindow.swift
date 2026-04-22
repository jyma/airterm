import AppKit

enum FocusDirection { case left, right, up, down }

final class TerminalWindow: NSWindow {
    private var rootPane: Pane!
    private var container: PaneContainerView!

    private weak var activeTerminalView: TerminalView? {
        didSet {
            oldValue?.isActive = false
            activeTerminalView?.isActive = true
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "AirTerm"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        minSize = NSSize(width: 480, height: 320)
        backgroundColor = Palette.background
        tabbingMode = .preferred
        tabbingIdentifier = "airterm.tab-group"

        guard let content = contentView else { return }

        let firstTV = makeTerminalView(frame: content.bounds)
        let firstLeaf = Pane.leaf(firstTV)
        self.rootPane = firstLeaf
        self.activeTerminalView = firstTV

        let container = PaneContainerView(frame: content.bounds, root: firstLeaf)
        container.autoresizingMask = [.width, .height]
        content.addSubview(container)
        self.container = container

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

        if let firstLeaf = rootPane.leaves.first, let newFocus = firstLeaf.terminalView {
            activeTerminalView = newFocus
            DispatchQueue.main.async { [weak self] in
                self?.makeFirstResponder(newFocus)
            }
        }
    }
}

enum Palette {
    /// Catppuccin Mocha base.
    static let background = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1.0)
    /// Catppuccin Mocha blue — active-pane border.
    static let accent = NSColor(srgbRed: 0.537, green: 0.706, blue: 0.98, alpha: 1.0)
}
