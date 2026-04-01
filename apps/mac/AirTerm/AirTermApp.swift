import SwiftUI

@main
struct AirTermApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar extra
        MenuBarExtra("AirTerm", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        // Main window (optional, opened from menu bar)
        Window("AirTerm", id: "main") {
            MainWindow()
                .environment(appState)
        }
        .defaultSize(width: 800, height: 600)

        // Pairing window
        Window("Pair Device", id: "pairing") {
            PairingView()
                .environment(appState)
        }
        .windowResizability(.contentSize)

        // Settings
        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private var menuBarIcon: String {
        switch appState.connectionState {
        case .connected: "terminal.fill"
        case .connecting: "terminal"
        case .disconnected: "terminal"
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
