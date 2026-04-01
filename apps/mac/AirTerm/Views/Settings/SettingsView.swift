import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var customServerURL = ""
    @State private var useCustomServer = false

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("Server") {
                Toggle("Use custom relay server", isOn: $useCustomServer)
                if useCustomServer {
                    TextField("Server URL", text: $customServerURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            appState.serverURL = customServerURL
                        }
                } else {
                    Text("relay.airterm.dev")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Paired Devices") {
                if appState.pairedDevices.isEmpty {
                    Text("No paired devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("Paired \(device.pairedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke", role: .destructive) {
                                // TODO: implement device revocation
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Device ID", value: String(appState.macDeviceId.prefix(8)) + "...")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .onAppear {
            let url = appState.serverURL
            useCustomServer = url != "https://relay.airterm.dev"
            customServerURL = url
        }
    }
}
