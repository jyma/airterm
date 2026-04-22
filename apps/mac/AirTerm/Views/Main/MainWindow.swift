import SwiftUI

// MARK: - Main Window

struct MainWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            terminalArea
        }
        .background(Color(nsColor: TerminalTheme.bg))
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(appState.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == appState.activeTabId,
                            onSelect: { appState.selectTab(tab.id) },
                            onClose: { appState.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.leading, 8)
            }

            Spacer()

            // New tab button
            Button(action: { appState.createTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("新建终端 ⌘T")
            .keyboardShortcut("t", modifiers: .command)
        }
        .frame(height: 36)
        .background(tabBarBackground)
    }

    private var tabBarBackground: some View {
        Color(nsColor: NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.094, green: 0.094, blue: 0.145, alpha: 1) // Mocha Mantle
                : NSColor(srgbRed: 0.902, green: 0.914, blue: 0.937, alpha: 1) // Latte Mantle
        })
    }

    // MARK: - Terminal Area

    private var terminalArea: some View {
        ZStack {
            if let activeId = appState.activeTabId {
                // Use ForEach + opacity to keep all terminals alive (preserve state)
                ForEach(appState.tabs) { tab in
                    TerminalTextView(sessionId: tab.id)
                        .opacity(tab.id == activeId ? 1 : 0)
                        .allowsHitTesting(tab.id == activeId)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab Item

private struct TabItemView: View {
    let tab: TerminalTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(tab.title)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            // Close button (visible on hover or active)
            if isActive || isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    private var tabBackground: some View {
        Group {
            if isActive {
                Color(nsColor: TerminalTheme.bg)
            } else if isHovering {
                Color(nsColor: TerminalTheme.bg).opacity(0.5)
            } else {
                Color.clear
            }
        }
    }
}
