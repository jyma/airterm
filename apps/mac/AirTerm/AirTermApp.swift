import SwiftUI

@main
struct AirTermApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Main window — must be first scene, auto-opens on launch
        WindowGroup("AirClaude", id: "main") {
            MainWindow()
                .environment(appState)
                .onAppear {
                    DebugLog.log("[App] Main window appeared")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 900, height: 620)

        // Menu bar extra
        MenuBarExtra("AirClaude", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        // Pairing window
        Window("配对新设备", id: "pairing") {
            PairingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)

        // Onboarding window
        Window("欢迎使用 AirClaude", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)

        // Settings
        Window("AirClaude 设置", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
    }

    private var menuBarIcon: String {
        switch appState.connectionState {
        case .connected: "wifi"
        case .connecting: "wifi.exclamationmark"
        case .disconnected: "wifi.slash"
        }
    }

    init() {
        _appState = State(initialValue: {
            let state = AppState()
            state.setup()
            return state
        }())
    }
}

/// AppDelegate — ensure app can receive keyboard input.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DebugLog.log("[AppDelegate] policy=regular, activated, isActive=\(NSApp.isActive)")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DebugLog.log("[AppDelegate] didBecomeActive")
        // Make the main window key when app activates
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
    }
}
