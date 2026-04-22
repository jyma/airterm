import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: TerminalWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load + seed config before any window is built so the first frame
        // already honours the user's theme / font / padding choices.
        _ = ConfigStore.shared
        ConfigStore.shared.startWatching()

        installMainMenu()

        let window = TerminalWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About AirTerm",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit AirTerm",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: nil, keyEquivalent: "n")

        let newTab = fileMenu.addItem(
            withTitle: "New Tab",
            action: #selector(NSWindow.newWindowForTab(_:)),
            keyEquivalent: "t"
        )
        newTab.keyEquivalentModifierMask = [.command]

        fileMenu.addItem(NSMenuItem.separator())

        let splitV = fileMenu.addItem(
            withTitle: "Split Vertically",
            action: #selector(TerminalWindow.splitPaneVertically(_:)),
            keyEquivalent: "d"
        )
        splitV.keyEquivalentModifierMask = [.command]

        let splitH = fileMenu.addItem(
            withTitle: "Split Horizontally",
            action: #selector(TerminalWindow.splitPaneHorizontally(_:)),
            keyEquivalent: "d"
        )
        splitH.keyEquivalentModifierMask = [.command, .shift]

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(
            withTitle: "Close Pane",
            action: #selector(TerminalWindow.closeActivePane(_:)),
            keyEquivalent: "w"
        )
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let nextPane = viewMenu.addItem(
            withTitle: "Next Pane",
            action: #selector(TerminalWindow.focusNextPane(_:)),
            keyEquivalent: "]"
        )
        nextPane.keyEquivalentModifierMask = [.command]

        let prevPane = viewMenu.addItem(
            withTitle: "Previous Pane",
            action: #selector(TerminalWindow.focusPreviousPane(_:)),
            keyEquivalent: "["
        )
        prevPane.keyEquivalentModifierMask = [.command]

        viewMenu.addItem(NSMenuItem.separator())

        let arrowMods: NSEvent.ModifierFlags = [.command, .option]
        let upKey = String(Unicode.Scalar(NSUpArrowFunctionKey)!)
        let downKey = String(Unicode.Scalar(NSDownArrowFunctionKey)!)
        let leftKey = String(Unicode.Scalar(NSLeftArrowFunctionKey)!)
        let rightKey = String(Unicode.Scalar(NSRightArrowFunctionKey)!)

        let left = viewMenu.addItem(
            withTitle: "Select Pane Left",
            action: #selector(TerminalWindow.focusPaneLeft(_:)),
            keyEquivalent: leftKey
        )
        left.keyEquivalentModifierMask = arrowMods

        let right = viewMenu.addItem(
            withTitle: "Select Pane Right",
            action: #selector(TerminalWindow.focusPaneRight(_:)),
            keyEquivalent: rightKey
        )
        right.keyEquivalentModifierMask = arrowMods

        let up = viewMenu.addItem(
            withTitle: "Select Pane Up",
            action: #selector(TerminalWindow.focusPaneUp(_:)),
            keyEquivalent: upKey
        )
        up.keyEquivalentModifierMask = arrowMods

        let down = viewMenu.addItem(
            withTitle: "Select Pane Down",
            action: #selector(TerminalWindow.focusPaneDown(_:)),
            keyEquivalent: downKey
        )
        down.keyEquivalentModifierMask = arrowMods

        viewMenu.addItem(NSMenuItem.separator())

        for i in 1...9 {
            let item = viewMenu.addItem(
                withTitle: "Select Tab \(i)",
                action: #selector(TerminalWindow.selectTabByTag(_:)),
                keyEquivalent: "\(i)"
            )
            item.keyEquivalentModifierMask = [.command]
            item.tag = i - 1
        }

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
