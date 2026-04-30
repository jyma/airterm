import AppKit

/// One tab inside a `TerminalWindow`. Owns its own pane tree, container view,
/// and tracks which terminal view inside the tree currently has focus. The
/// window switches tabs by reparenting the container, never by rebuilding it,
/// so PTY sessions and Metal renderers keep running across tab switches.
final class Tab {
    let id = UUID()
    var rootPane: Pane
    weak var activeTerminalView: TerminalView?
    let paneContainer: PaneContainerView

    init(rootPane: Pane, container: PaneContainerView) {
        self.rootPane = rootPane
        self.paneContainer = container
        self.activeTerminalView = rootPane.leaves.first?.terminalView
    }

    /// All terminal views inside this tab's pane tree. Used by the window when
    /// it tears down a tab so it can stop every PTY session in the subtree.
    var allTerminalViews: [TerminalView] {
        rootPane.leaves.compactMap(\.terminalView)
    }

    /// Display title — basename of the active session's cwd, or a fallback
    /// when the shell hasn't reported a cwd yet (pre-OSC-7).
    var title: String {
        guard let cwd = activeTerminalView?.session.cwd, !cwd.isEmpty else {
            return "Terminal"
        }
        if cwd == NSHomeDirectory() { return "~" }
        return (cwd as NSString).lastPathComponent
    }

    /// Nerd Font glyph chosen by inspecting the cwd. Falls back to a generic
    /// folder icon when no project markers are present.
    var icon: String {
        let cwd = activeTerminalView?.session.cwd ?? ""
        return TabIcon.iconFor(cwd: cwd)
    }
}

/// Picks a Nerd Font glyph for a tab title based on what files live at the
/// session's cwd. Higher-priority markers (language ecosystem, project type)
/// override lower-priority ones (generic folder, home directory).
enum TabIcon {
    private static let projectMarkers: [(String, String)] = [
        ("Cargo.toml",       "\u{e7a8}"),  //   rust
        ("go.mod",           "\u{e627}"),  //   go
        ("package.json",     "\u{e718}"),  //   node
        ("pnpm-lock.yaml",   "\u{e718}"),
        ("yarn.lock",        "\u{e718}"),
        ("bun.lockb",        "\u{e718}"),
        ("pyproject.toml",   "\u{e73c}"),  //   python
        ("requirements.txt", "\u{e73c}"),
        ("setup.py",         "\u{e73c}"),
        (".python-version",  "\u{e73c}"),
        ("Gemfile",          "\u{e791}"),  //   ruby
        ("Package.swift",    "\u{e755}"),  //   swift
        ("Podfile",          "\u{e755}"),
        ("CMakeLists.txt",   "\u{e61e}"),  //   cmake
        ("Makefile",         "\u{e779}"),  //   make
        ("docker-compose.yml", "\u{f308}"),//   docker
        ("Dockerfile",       "\u{f308}"),
    ]

    static func iconFor(cwd: String) -> String {
        guard !cwd.isEmpty else { return "\u{f120}" }   //   terminal

        let url = URL(fileURLWithPath: cwd)
        let fm = FileManager.default

        for (file, glyph) in projectMarkers {
            if fm.fileExists(atPath: url.appendingPathComponent(file).path) {
                return glyph
            }
        }

        if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
            return "\u{f1d3}"   //   git
        }

        if cwd == NSHomeDirectory() {
            return "\u{f015}"   //   home
        }

        return "\u{f07b}"       //   folder
    }
}
