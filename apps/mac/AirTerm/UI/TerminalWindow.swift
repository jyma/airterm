import AppKit

final class TerminalWindow: NSWindow {
    private var rootPane: Pane!
    private weak var activeTerminalView: TerminalView?
    private var container: PaneContainerView!

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
}
