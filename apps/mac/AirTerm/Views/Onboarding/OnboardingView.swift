import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep {
        case welcome
        case axPermission
        case pairing
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Window chrome
            HStack { Spacer() }
                .frame(height: 1)

            VStack(spacing: 24) {
                // Logo
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi")
                            .font(.title)
                            .foregroundStyle(.blue)
                        Text("AirClaude")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    Text("隔空指挥你的 Claude Code 会话")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Steps
                VStack(spacing: 12) {
                    // Step 1: Accessibility Permission
                    StepCard(
                        number: 1,
                        title: "授予辅助功能权限",
                        subtitle: "用于读取终端窗口内容，发现 Claude Code 会话",
                        isActive: step == .welcome || step == .axPermission,
                        isCompleted: step == .pairing || step == .done
                    ) {
                        if appState.accessibilityEnabled {
                            Label("已授权", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Button("授权") {
                                appState.requestAccessibility()
                                step = .axPermission
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    // Step 2: Pair Device
                    StepCard(
                        number: 2,
                        title: "配对手机",
                        subtitle: "扫码连接，随时随地远程操控",
                        isActive: step == .pairing,
                        isCompleted: step == .done
                    ) {
                        if !appState.pairedDevices.isEmpty {
                            Label("已配对", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if step == .pairing || step == .welcome {
                            Button("配对") {
                                Task { try? await appState.startPairing() }
                                openWindow(id: "pairing")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(step != .pairing && step != .welcome)
                        }
                    }
                }

                // Skip / Continue
                HStack {
                    if step != .done {
                        Button("跳过") {
                            UserDefaults.standard.set(true, forKey: "onboarding-completed")
                            openWindow(id: "main")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }

                    Spacer()

                    if step == .done || !appState.pairedDevices.isEmpty {
                        Button("开始使用") {
                            UserDefaults.standard.set(true, forKey: "onboarding-completed")
                            openWindow(id: "main")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }

                // Footer
                Text("端到端加密 · 服务器零知识 · 无需注册")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 380)
        .onChange(of: appState.accessibilityEnabled) { _, enabled in
            if enabled { step = .pairing }
        }
        .onChange(of: appState.pairedDevices.count) { _, count in
            if count > 0 { step = .done }
        }
    }
}

struct StepCard<Action: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    let isActive: Bool
    let isCompleted: Bool
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 12) {
            // Step number
            ZStack {
                Circle()
                    .fill(isActive || isCompleted ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(isActive || isCompleted ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            action
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
