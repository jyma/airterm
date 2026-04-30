import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: TerminalWindow?
    private var pairingWindow: PairingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run the Noise IK self-test at launch in DEBUG builds. This catches
        // any drift between the Swift port and the TS reference (which the
        // web initiator imports) the moment we start the app, instead of at
        // first pair attempt where the failure mode is much harder to trace.
        #if DEBUG
        if let failure = Noise.runSelfTest() {
            assertionFailure("Noise self-test failed: \(failure)")
            DebugLog.log("Noise self-test failed: \(failure)")
        } else {
            DebugLog.log("Noise self-test passed")
        }
        #endif

        // Register bundled fonts before anything tries to resolve them by name.
        BundledFonts.registerAll()

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

    // MARK: - Theme menu actions

    @objc func selectThemeByTag(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              item.tag >= 0, item.tag < Theme.builtinNames.count else { return }
        ConfigStore.shared.setTheme(named: Theme.builtinNames[item.tag])
    }

    @objc func cycleThemeForward(_ sender: Any?) {
        ConfigStore.shared.cycleTheme(forward: true)
    }

    @objc func toggleCommandPalette(_ sender: Any?) {
        CommandPalette.shared.toggle(from: NSApp.keyWindow)
    }

    @objc func openPairingWindow(_ sender: Any?) {
        // Lazy-create so the user pays the network init cost only when
        // they actually want to pair. Reuse an existing window so a
        // double-click on the menu item just brings the panel forward.
        if pairingWindow == nil {
            let serverURL = ProcessInfo.processInfo.environment["AIRTERM_RELAY_URL"]
                ?? "https://relay.airterm.dev"
            let macDeviceId = MacDeviceID.stableId()
            let macName = Host.current().localizedName ?? "Mac"
            let service = PairingService(
                serverURL: serverURL,
                macDeviceId: macDeviceId,
                macName: macName
            )
            pairingWindow = PairingWindow(pairingService: service)
        }
        pairingWindow?.center()
        pairingWindow?.makeKeyAndOrderFront(nil)
        pairingWindow?.startPairing()
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

        let pair = fileMenu.addItem(
            withTitle: "Pair New Device…",
            action: #selector(AppDelegate.openPairingWindow(_:)),
            keyEquivalent: ""
        )
        pair.target = self

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

        // Command palette is reachable via Edit > Command Palette so the
        // ⇧⌘P binding flows through the standard responder chain (no
        // global event monitor needed; the menu owns the shortcut).
        let palette = editMenu.addItem(
            withTitle: "Command Palette",
            action: #selector(AppDelegate.toggleCommandPalette(_:)),
            keyEquivalent: "p"
        )
        palette.keyEquivalentModifierMask = [.command, .shift]
        palette.target = self

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

        viewMenu.addItem(NSMenuItem.separator())

        let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        for (i, name) in Theme.builtinNames.enumerated() {
            // Dark themes come first in `builtinNames`; light themes follow
            // after index 8. Insert a separator at the boundary for clarity.
            if i == 8 { themeMenu.addItem(NSMenuItem.separator()) }

            let keyEq = i < 8 ? "\(i + 1)" : ""
            let item = themeMenu.addItem(
                withTitle: name,
                action: #selector(AppDelegate.selectThemeByTag(_:)),
                keyEquivalent: keyEq
            )
            if !keyEq.isEmpty {
                item.keyEquivalentModifierMask = [.command, .control]
            }
            item.tag = i
            item.target = self
        }
        themeMenu.addItem(NSMenuItem.separator())
        let cycle = themeMenu.addItem(
            withTitle: "Next Theme",
            action: #selector(AppDelegate.cycleThemeForward(_:)),
            keyEquivalent: "t"
        )
        cycle.keyEquivalentModifierMask = [.command, .control]
        cycle.target = self
        themeMenuItem.submenu = themeMenu
        viewMenu.addItem(themeMenuItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
